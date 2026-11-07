module Research
  class Policy
    REQUIRED = %w[subscription_verified automated_read text_storage embedding_storage private_display
                  openai_processing openai_retention_approved backup_retention_approved openai_account_verified].freeze
    attr_reader :settings

    def initialize(user, configuration: nil)
      configuration ||= Rails.application.config_for(:research_ingestion).to_h
      owners = configuration.is_a?(Hash) ? configuration.deep_stringify_keys.fetch("approved_owners", {}) : nil
      @settings = owners.is_a?(Hash) ? owners.fetch(user.id.to_s, {}) : nil
      raise Error.new("research_policy_invalid") unless @settings.is_a?(Hash)
    end

    def check!(request)
      if request.provider == "synthetic"
        unless request.listing_identity == "SYNTH:ALPHA" && request.fiscal_year == 2026 &&
               request.fiscal_quarter == 3 && %w[v1 v2].include?(request.fixture_version)
          raise Error.new("source_not_allowlisted")
        end
      else
        unless REQUIRED.all? { |name| settings[name] == true } &&
               settings["approval_reference"].is_a?(String) && settings["approval_reference"].present? &&
               settings["source_kinds"].is_a?(Array) && settings["source_kinds"].include?(request.source_kind) &&
               settings["listings"].is_a?(Array) && settings["listings"].include?(request.listing_identity) &&
               valid_limit?("retention_seconds", 1..2_592_000) &&
               valid_limit?("freshness_seconds", 1..86_400) &&
               valid_limit?("daily_source_requests", 1..30) &&
               settings["freshness_seconds"] <= settings["retention_seconds"] && expiry > Time.current
          raise Error.new("research_permission_required")
        end
      end
      check_space!(request)
      self
    end

    def reference(request)
      request.provider == "synthetic" ? "original-public-fixture-v1" : settings.fetch("approval_reference")
    end

    def deadline(request)
      request.provider == "synthetic" ? Time.current + 30.days : expiry
    end

    def retention(request)
      request.provider == "synthetic" ? 30.days.to_i : settings.fetch("retention_seconds")
    end

    def freshness(request)
      request.provider == "synthetic" ? 1.day.to_i : settings.fetch("freshness_seconds")
    end

    def history?(request)
      request.provider == "synthetic" || settings["historical_storage"] == true
    end

    private

    def check_space!(request)
      space = request.space.reload
      expected = request.provider == "synthetic" ? ["synthetic", "fixture-1536", "sha256-v1"] :
                                                 ["openai", "text-embedding-3-small", "text-embedding-3-small"]
      unless [space.provider, space.model, space.model_version] == expected &&
             space.dimensions == 1536 && space.distance == "cosine" && space.state != "retired" &&
             space.preprocessing_version == Chunker::PREPROCESSING && space.chunker_version == Chunker::VERSION
        raise Error.new("embedding_space_not_allowlisted")
      end
    end

    def expiry
      value = settings["expires_at"]
      return Time.at(0) unless value.is_a?(String) && value.match?(/T.*(?:Z|[+-]\d{2}:\d{2})\z/)
      Time.iso8601(value)
    rescue ArgumentError
      Time.at(0)
    end

    def valid_limit?(name, range)
      settings[name].is_a?(Integer) && range.cover?(settings[name])
    end
  end
end
