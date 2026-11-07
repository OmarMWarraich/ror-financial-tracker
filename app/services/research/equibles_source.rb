module Research
  class EquiblesSource
    def initialize(transport: nil)
      @transport = transport
    end

    def call(request, before_request:, api_key:)
      ticker = request.listing_identity.delete_prefix("US:")
      path = "/v1/stocks/#{URI.encode_www_form_component(ticker)}/earnings-calls/#{request.fiscal_year}/#{request.fiscal_quarter}"
      transport = @transport || EquiblesTransport.new(on_headers: ->(status, headers) {
        SourceQuota.observe_connection!(request.user.equibles_connection, status, headers,
          settings: Policy.new(request.user).settings)
      })
      get = ->(suffix) do
        remaining = before_request.call
        transport.call(uri: URI("https://api.equibles.com#{suffix}"), api_key: api_key, timeout: [5.0, remaining].min)
      end
      event = get.call(path)
      identity!(event, request, ticker)
      unless event["id"].is_a?(String) && event["id"].match?(/\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/i) &&
             event["isTombstoned"] == false
        raise Error.new("invalid_source_event")
      end
      transcript_data = request.source_kind == "earnings_transcript" ? transcript(event, request, ticker, path, get) : nil
      parts = transcript_data ? transcript_data.fetch(:parts) : brief(event, request, ticker, get)
      now = Time.current
      call_time = instant(event["callDate"])
      {
        parts: parts, event_at: event["callDateIsPeriodEnd"] == false ? call_time : nil,
        published_at: nil, known_at: nil, received_at: now,
        metadata: {
          "synthetic" => false,
          "provider_event_id" => event["id"], "listing_identity" => request.listing_identity,
          "fiscal_year" => request.fiscal_year, "fiscal_quarter" => request.fiscal_quarter,
          "source_kind" => request.source_kind, "raw_call_date" => event["callDate"],
          "call_date_is_period_end" => event["callDateIsPeriodEnd"], "status" => event["status"],
          "source_publication_unknown" => true, "known_available_unknown" => true,
          "corrections" => (corrections(event["corrections"]) + (transcript_data ? transcript_data[:corrections] : [])).uniq
        }
      }
    end

    private

    def transcript(event, request, ticker, path, get)
      unless event["hasTranscript"] == true && event["partialRecording"] == false && event["presentationOnly"] == false
        raise Error.new("transcript_unavailable_or_partial")
      end
      parts = []
      page_corrections = []
      total = nil
      2.times do
        offset = parts.size
        page = get.call("#{path}/speakers?limit=50&offset=#{offset}")
        identity!(page, request, ticker)
        data = page["data"]
        unless page["eventId"] == event["id"] && page["callDate"] == event["callDate"] &&
               page["isFiledRecord"] == false && data.is_a?(Array) && data.size.between?(1, 50) &&
               page["offset"] == offset && page["turnCount"] == data.size &&
               page["totalTurnCount"].is_a?(Integer) && page["totalTurnCount"].positive? &&
               [true, false].include?(page["hasMore"])
          raise Error.new("invalid_transcript_page")
        end
        total ||= page["totalTurnCount"]
        if total > 100
          raise Error.new("transcript_pagination_limit")
        end
        unless total == page["totalTurnCount"] && page["hasMore"] == (offset + data.size < total) &&
               offset + data.size <= total
          raise Error.new("transcript_changed_during_fetch")
        end
        page_corrections.concat(corrections(page["corrections"]))
        data.each_with_index do |turn, index|
          unless turn.is_a?(Hash) && turn["speakerIndex"].is_a?(Integer) &&
                 [turn["speakerName"], turn["speakerRole"]].all? { |value| value.nil? || (value.is_a?(String) && value.length <= 256) }
            raise Error.new("invalid_source_content")
          end
          start_seconds = seconds(turn["startSeconds"])
          end_seconds = seconds(turn["endSeconds"])
          if start_seconds && end_seconds && end_seconds < start_seconds
            raise Error.new("invalid_source_time")
          end
          parts << {
            "text" => turn["text"], "speaker" => turn["speakerName"], "speaker_role" => turn["speakerRole"],
            "speaker_index" => turn["speakerIndex"], "turn_index" => offset + index,
            "section" => "speaker_turn", "start_seconds" => start_seconds, "end_seconds" => end_seconds
          }
        end
        return { parts: parts, corrections: page_corrections.uniq } unless page["hasMore"]
      end
      raise Error.new("transcript_pagination_limit")
    end

    def brief(event, request, ticker, get)
      response = get.call("/v1/stocks/#{URI.encode_www_form_component(ticker)}/earnings-briefs?limit=1&fiscalYear=#{request.fiscal_year}&fiscalQuarter=#{request.fiscal_quarter}")
      raise Error.new("listing_changed") unless response["listingNotice"].nil?
      data = response["data"]
      raise Error.new("brief_unavailable") unless data.is_a?(Array) && data.size == 1 && data.first.is_a?(Hash)
      item = data.first
      unless item["fiscalYear"] == request.fiscal_year && item["fiscalQuarter"] == request.fiscal_quarter &&
             item["callDate"] == event["callDate"]
        raise Error.new("source_identity_mismatch")
      end
      parts = []
      parts << { "text" => item["tldr"], "section" => "tldr" } if item["tldr"]
      %w[bullish bearish].each do |section|
        values = item[section]
        raise Error.new("invalid_source_content") unless values.nil? || values.is_a?(Array)
        values.to_a.each { |text| parts << { "text" => text, "section" => section } }
      end
      quotes = item["quotes"]
      raise Error.new("invalid_source_content") unless quotes.nil? || quotes.is_a?(Array)
      quotes.to_a.each do |quote|
        raise Error.new("invalid_source_content") unless quote.is_a?(Hash)
        parts << { "text" => quote["text"], "section" => "quote", "speaker" => quote["speakerName"],
                   "speaker_role" => quote["speakerRole"], "start_seconds" => seconds(quote["startSeconds"]) }
      end
      %w[narrativeShift guidanceComparison].each do |section|
        comparison = item[section]
        next if comparison.nil?
        raise Error.new("invalid_source_content") unless comparison.is_a?(Hash)
        parts << { "text" => JSON.generate(comparison.sort.to_h), "section" => section,
                   "representation" => "provider_structured_json" }
      end
      parts
    end

    def identity!(value, request, ticker)
      unless value.is_a?(Hash) && value["ticker"] == ticker && value["fiscalYear"] == request.fiscal_year &&
             value["fiscalQuarter"] == request.fiscal_quarter
        raise Error.new("source_identity_mismatch")
      end
    end

    def instant(value)
      return nil if value.nil?
      raise Error.new("invalid_source_time") unless value.is_a?(String)
      DateTime.iso8601(value)
      return nil unless value.match?(/T.*(?:Z|[+-]\d{2}:\d{2})\z/)
      Time.iso8601(value).utc
    rescue ArgumentError
      raise Error.new("invalid_source_time")
    end

    def seconds(value)
      return nil if value.nil?
      unless value.is_a?(Numeric) && value.real? && value.to_f.finite? && value >= 0
        raise Error.new("invalid_source_time")
      end
      value
    end

    def corrections(value)
      return [] if value.nil?
      unless value.is_a?(Array) && value.size <= 100 && value.all? { |item| item.is_a?(Hash) }
        raise Error.new("invalid_source_corrections")
      end
      value.map { |item| item.slice("metricLabel", "transcriptQuote", "transcriptValue", "filingValue", "filingForm", "filingFiledDate", "note") }
    end
  end
end
