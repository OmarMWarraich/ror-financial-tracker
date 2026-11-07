module Research
  module Agent
    class FixtureTools
      EVENT_ID = "a0000000-0000-4000-8000-000000000003"

      def initialize(registry)
        @registry = registry
      end

      def discover!
        tools = ToolRegistry::FIELDS.map do |name, fields|
          schema = { "type" => "object", "properties" => fields.to_h { |key|
            [key, { "type" => key == "ticker" ? "string" : "integer" }]
          }, "required" => ["ticker"] }
          Struct.new(:name, :input_schema, :annotations).new(name, schema, nil)
        end
        @registry.register!(tools)
        @registry.definitions
      end

      def call(name, arguments, forbidden: [])
        @registry.validate!(name, arguments)
        text = case name
        when "GetEarningsCallEvent"
          "# Original fictional Alpha earnings call\n- Ticker: ALPHA\n- Event id: #{EVENT_ID}\n" \
            "- Fiscal period: FY2026 Q3\n- Call date (UTC): 2026-10-28\n- Status: Concluded\n\n" \
            "Artefacts:\n- Transcript: available (Original fixture)"
        when "GetEarningsBrief"
          "# ALPHA - earnings brief\n\n## FY2026 Q3 (call 2026-10-28)\n\n" \
            "Synthetic Alpha reported revenue of 120 demonstration units. This is original fictional data, not investment advice."
        when "GetEarningsCallTranscript"
          raise Research::Error.new("fixture_page_absent") unless arguments["offset"] == 0
          "# Original Alpha Q3 FY2026 Earnings Call - speakers\n- Ticker: ALPHA\n" \
            "- Call date (UTC): 2026-10-28\n- Turns: 1-2 of 2\n\n" \
            "Fictional Chief Executive: revenue was 120 demonstration units.\nOperator: this is original fictional data."
        end
        { "text" => Agent.safe_text!(text, forbidden: forbidden), "structured" => nil, "synthetic" => true }
      end

      def close
      end

      def cancel!
      end
    end
  end
end
