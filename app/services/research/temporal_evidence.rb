module Research
  class TemporalEvidence
    FIELDS = %w[event_at published_at known_at received_at verified_at indexed_at fresh_until expires_at].freeze
    KNOWN_BASES = %w[original_fixture source_revision_publication].freeze

    def self.source(data, provider:)
      values = %i[event_at published_at known_at received_at].index_with { |name| data[name] }
      values.each_value do |value|
        unless value.nil? || ((value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)) &&
                             value.year.between?(1900, 2200))
          raise Error.new("invalid_source_time")
        end
      end
      raw = data.fetch(:metadata)["raw_call_date"]
      if values[:event_at] && raw && (data[:metadata]["call_date_is_period_end"] != false ||
                                     !raw.is_a?(String) || !raw.match?(/T.*(?:Z|[+-]\d{2}:\d{2})\z/))
        raise Error.new("invalid_source_time")
      end
      event_basis = if raw && data[:metadata]["call_date_is_period_end"] == true
        "fiscal_period_placeholder"
      elsif raw && values[:event_at].nil?
        "date_or_zone_unconfirmed"
      else
        provider == "synthetic" ? "original_fixture" : "provider_call_date"
      end
      proof = values.stringify_keys.transform_values { |value| value&.iso8601(6) }
      proof.delete("received_at")
      metadata = {
        "event_at" => entry(values[:event_at], event_basis, raw: raw),
        "published_at" => entry(values[:published_at], provider == "synthetic" ? "original_fixture" : "source_publication"),
        "known_at" => entry(values[:known_at], provider == "synthetic" ? "original_fixture" : "source_revision_publication"),
        "received_at" => { "basis" => "application_receipt", "confidence" => "confirmed", "zone" => "UTC" },
        "verified_at" => { "basis" => "application_source_validation", "confidence" => "confirmed", "zone" => "UTC" },
        "indexed_at" => { "basis" => "application_index", "confidence" => "confirmed", "zone" => "UTC" },
        "fresh_until" => { "basis" => "verified_at_plus_recheck_interval", "confidence" => "confirmed", "zone" => "UTC" },
        "expires_at" => { "basis" => "approval_and_retention_limit", "confidence" => "confirmed", "zone" => "UTC" }
      }
      { values: values, metadata: metadata, fingerprint: proof.merge("basis" => metadata.slice("event_at", "published_at", "known_at")) }
    end

    def self.entry(value, basis, raw: nil)
      { "basis" => value.nil? && basis != "fiscal_period_placeholder" && basis != "date_or_zone_unconfirmed" ? "unknown" : basis,
        "confidence" => value.nil? ? "unknown" : "confirmed",
        "zone" => value&.strftime("%:z"), "raw" => raw, "utc" => value&.getutc&.iso8601(6) }.compact
    end

    def self.describe(revision)
      FIELDS.index_with do |name|
        value = revision.public_send(name)
        proof = revision.temporal_metadata.fetch(name, { "basis" => "legacy_unverified", "confidence" => "unknown" })
        proof.merge("value" => value&.utc&.iso8601(6), "confidence" => value.nil? ? "unknown" : proof.fetch("confidence", "unknown"))
      end
    end
  end
end
