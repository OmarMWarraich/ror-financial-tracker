module Research
  module Agent
    class Policy
      def self.fingerprints(user, run, settings)
        values = { "policy" => Digest::SHA256.hexdigest(JSON.generate(settings.sort.to_h)) }
        return values if run.provider == "fixture"
        key = ENV["OPENAI_API_KEY"].to_s.strip
        unless key.present? && key.valid_encoding? && key.length <= 4096 && !key.match?(/\s/)
          raise Research::Error.new("openai_credentials_required")
        end
        values["openai"] = Digest::SHA256.hexdigest(key)
        if %w[live_mcp mixed].include?(run.selectors["evidence_mode"])
          unless EquiblesConnection.encryption_configured? && user.equibles_connection
            raise Research::Error.new("equibles_credentials_required")
          end
          values["equibles"] = Digest::SHA256.hexdigest(user.equibles_connection.reload.read_attribute_before_type_cast(:api_key).to_s)
        end
        values
      end

      def initialize(user, configuration: nil)
        @user = user
        @configuration = configuration
      end

      def check!(run)
        RestoreGate.check!
        return {} if run.provider == "fixture" && run.selectors["listing_identity"] == "SYNTH:ALPHA" &&
          run.selectors["fiscal_year"] == 2026 && run.selectors["fiscal_quarter"] == 3
        settings = Research::Policy.new(@user, configuration: @configuration).settings
        expiry = settings["expires_at"]
        unless settings["agent_enabled"] == true && settings["derived_answers"] == true &&
               Research::Policy::REQUIRED.all? { |key| settings[key] == true } &&
               Research::Policy.backup_controls?(settings) &&
               settings["inference_models"].is_a?(Array) && settings["inference_models"].include?(MODEL) &&
               settings["approval_reference"].is_a?(String) && settings["approval_reference"].present? &&
               settings["listings"].is_a?(Array) && settings["listings"].include?(run.selectors["listing_identity"]) &&
               settings["source_kinds"].is_a?(Array) && (settings["source_kinds"] & %w[earnings_brief earnings_transcript]).any? &&
               settings["retention_seconds"].is_a?(Integer) && settings["retention_seconds"].between?(1, 2_592_000) &&
               settings["freshness_seconds"].is_a?(Integer) && settings["freshness_seconds"].between?(1, 86_400) &&
               settings["freshness_seconds"] <= settings["retention_seconds"] &&
               settings["daily_source_requests"].is_a?(Integer) && settings["daily_source_requests"].between?(1, 30) &&
               expiry.is_a?(String) && expiry.match?(/T.*(?:Z|[+-]\d{2}:\d{2})\z/) && Time.iso8601(expiry) > Time.current
          raise Research::Error.new("agent_permission_required")
        end
        if %w[live_mcp mixed].include?(run.selectors["evidence_mode"])
          unless settings["mcp_enabled"] == true && settings["mcp_tools"].is_a?(Array) &&
                 (settings["mcp_tools"] - ToolRegistry::FIELDS.keys).empty? &&
                 settings["mcp_tools"].include?("GetEarningsCallEvent")
            raise Research::Error.new("mcp_permission_required")
          end
        end
        if run.selectors["query_mode"] == "as_of" && settings["historical_storage"] != true
          raise Research::Error.new("historical_permission_required")
        end
        settings
      rescue ArgumentError
        raise Research::Error.new("agent_policy_invalid"), cause: nil
      end
    end
  end
end
