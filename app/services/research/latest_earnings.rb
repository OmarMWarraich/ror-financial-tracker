module Research
  class LatestEarnings
    UUID = /\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/i

    def initialize(transport: EquiblesTransport.new)
      @transport = transport
    end

    def call(provider:, listing_identity:, before_request:, api_key: nil)
      now = Time.current
      if provider == "synthetic"
        raise Error.new("source_not_allowlisted") unless listing_identity == "SYNTH:ALPHA"
        return { "provider_event_id" => "original-alpha-2026-q3", "fiscal_year" => 2026, "fiscal_quarter" => 3,
                 "event_at" => "2026-10-28T18:00:00Z", "observed_at" => now.iso8601(6), "basis" => "original_fixture",
                 "has_transcript" => true, "transcript_complete" => true }
      end
      ticker = listing_identity.delete_prefix("US:")
      base = "https://api.equibles.com/v1/stocks/#{URI.encode_www_form_component(ticker)}"
      get = ->(path) do
        remaining = before_request.call
        @transport.call(uri: URI("#{base}#{path}"), api_key: api_key, timeout: [5.0, remaining].min)
      end
      page = get.call("/investor-events?eventType=EarningsCall&includeUncaptured=true&limit=50&offset=0")
      meta = page.is_a?(Hash) ? page["meta"] : nil
      unless page.is_a?(Hash) && page["listingNotice"].nil? && page["data"].is_a?(Array) && page["data"].size <= 50 &&
             meta.is_a?(Hash) && meta["offset"] == 0 && meta["limit"] == 50 && meta["count"] == page["data"].size &&
             [true, false].include?(meta["hasMore"]) &&
             (meta["total"].nil? || (meta["total"].is_a?(Integer) && meta["total"] >= meta["count"] &&
                                    meta["hasMore"] == (meta["total"] > meta["count"])))
        raise Error.new("invalid_latest_event_page")
      end
      page["data"].each { |event| validate!(event) }
      unknown = page["data"].find { |event| !event["callDate"].match?(/T.*(?:Z|[+-]\d{2}:\d{2})\z/) }
      if unknown
        return { "reason" => "latest_event_time_unknown", "unconfirmed_call_date" => unknown["callDate"], "observed_at" => now.iso8601(6) }
      end
      candidates = page["data"].map do |event|
        [event, Time.iso8601(event.fetch("callDate"))]
      end
      unless candidates.map { |event, _| event["id"] }.uniq.size == candidates.size &&
             candidates.each_cons(2).all? { |first, second| first.last >= second.last }
        raise Error.new("latest_event_order_unknown")
      end
      candidate = candidates.find { |_, time| time <= now }
      unless candidate
        return { "reason" => meta["hasMore"] ? "latest_event_window_exhausted" : "latest_event_unavailable", "observed_at" => now.iso8601(6) }
      end
      row = candidate.first
      if row["callDateIsPeriodEnd"] || row["isTombstoned"] == true
        return { "reason" => "latest_event_unconfirmed_or_unavailable", "observed_at" => now.iso8601(6) }
      end
      event = get.call("/earnings-calls/#{row['fiscalYear']}/#{row['fiscalQuarter']}")
      validate!(event)
      unless event["ticker"] == ticker && %w[id fiscalYear fiscalQuarter callDate].all? { |field| event[field] == row[field] }
        raise Error.new("latest_event_changed")
      end
      if event["callDateIsPeriodEnd"] || event["isTombstoned"] == true
        return { "reason" => "latest_event_unconfirmed_or_unavailable", "observed_at" => now.iso8601(6) }
      end
      { "provider_event_id" => event["id"], "fiscal_year" => event["fiscalYear"], "fiscal_quarter" => event["fiscalQuarter"],
        "event_at" => Time.iso8601(event["callDate"]).utc.iso8601(6), "observed_at" => Time.current.iso8601(6),
        "basis" => "equibles_investor_events_and_exact_event", "has_transcript" => event["hasTranscript"] == true,
        "transcript_complete" => event["partialRecording"] == false && event["presentationOnly"] == false }
    rescue ArgumentError, KeyError
      raise Error.new("invalid_latest_event_time")
    end

    private

    def validate!(event)
      unless event.is_a?(Hash) && event["id"].is_a?(String) && event["id"].match?(UUID) &&
             event["eventType"] == "EarningsCall" && event["fiscalYear"].is_a?(Integer) && event["fiscalYear"].between?(1900, 2200) &&
             event["fiscalQuarter"].is_a?(Integer) && event["fiscalQuarter"].between?(1, 4) &&
             [true, false].include?(event["callDateIsPeriodEnd"]) &&
             event["callDate"].is_a?(String)
        raise Error.new("invalid_latest_event")
      end
      DateTime.iso8601(event["callDate"])
    end
  end
end
