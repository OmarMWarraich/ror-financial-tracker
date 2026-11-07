require "json_schemer"

module Research
  module Agent
    class ToolRegistry
      FIELDS = {
        "GetEarningsCallEvent" => %w[ticker fiscalYear fiscalQuarter],
        "GetEarningsBrief" => %w[ticker fiscalYear fiscalQuarter limit],
        "GetEarningsCallTranscript" => %w[ticker fiscalYear fiscalQuarter limit offset]
      }.freeze
      DESCRIPTIONS = {
        "GetEarningsCallEvent" => "Read the event metadata for the selected exact fiscal period.",
        "GetEarningsBrief" => "Read one approved brief for the selected exact fiscal period, not an inferred latest brief.",
        "GetEarningsCallTranscript" => "Read at most 50 transcript turns for the selected exact fiscal period."
      }.freeze

      def initialize(ticker:, year:, quarter:)
        unless ticker.is_a?(String) && ticker.match?(/\A[A-Z][A-Z0-9.-]{0,19}\z/) &&
               year.is_a?(Integer) && year.between?(1900, 2200) && (1..4).cover?(quarter)
          raise Research::Error.new("invalid_agent_tool_scope")
        end
        @ticker, @year, @quarter = ticker, year, quarter
        @discovered = {}
      end

      def register!(tools)
        tools.each do |tool|
          next unless FIELDS.key?(tool.name)
          raise Research::Error.new("duplicate_mcp_tool") if @discovered.key?(tool.name)
          schema = tool.input_schema
          properties = schema.is_a?(Hash) ? schema["properties"] : nil
          unless schema.is_a?(Hash) && schema["type"] == "object" && properties.is_a?(Hash) &&
                 properties.keys.sort == FIELDS.fetch(tool.name).sort &&
                 [nil, true, false].include?(schema["additionalProperties"]) &&
                 [nil, "https://json-schema.org/draft/2020-12/schema", "http://json-schema.org/draft-07/schema#"].include?(schema["$schema"]) &&
                 Array(schema["required"]).all? { |key| FIELDS.fetch(tool.name).include?(key) } &&
                 Array(schema["required"]).include?("ticker") &&
                 properties.all? { |key, value| safe_property?(key, value) } &&
                 (schema.keys - %w[type properties required additionalProperties description title $schema]).empty? &&
                 (tool.annotations.nil? || (tool.annotations.is_a?(Hash) && tool.annotations["readOnlyHint"] != false))
            raise Research::Error.new("mcp_tool_schema_changed")
          end
          @discovered[tool.name] = schema.deep_dup
        end
      end

      def definitions
        @discovered.keys.sort.map { |name|
          { type: :function, name: name, description: DESCRIPTIONS.fetch(name), strict: true, parameters: local_schema(name) }
        }
      end

      def validate!(name, arguments)
        unless @discovered.key?(name) && arguments.is_a?(Hash) &&
               JSONSchemer.schema(local_schema(name)).valid?(arguments) &&
               JSONSchemer.schema(@discovered.fetch(name)).valid?(arguments)
          raise Research::Error.new("agent_tool_not_authorized")
        end
        arguments
      end

      private

      def safe_property?(key, value)
        return false unless value.is_a?(Hash) &&
          (value.keys - %w[type description title default minimum maximum]).empty?
        return false unless %w[minimum maximum].all? { |bound|
          !value.key?(bound) || (value[bound].is_a?(Numeric) && value[bound].real? && value[bound].to_f.finite?)
        }
        expected = key == "ticker" ? "string" : "integer"
        type = value["type"]
        type == expected || (type.is_a?(Array) && type.sort == [expected, "null"].sort)
      end

      def local_schema(name)
        fixed = { "ticker" => @ticker, "fiscalYear" => @year, "fiscalQuarter" => @quarter, "limit" => name == "GetEarningsBrief" ? 1 : 50 }
        properties = FIELDS.fetch(name).to_h do |key|
          value = key == "offset" ? [0, 50] : [fixed.fetch(key)]
          [key, { "type" => key == "ticker" ? "string" : "integer", "enum" => value }]
        end
        { "type" => "object", "properties" => properties, "required" => properties.keys, "additionalProperties" => false }
      end
    end
  end
end
