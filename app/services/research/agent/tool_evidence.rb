module Research
  module Agent
    class ToolEvidence
      attr_reader :event

      def initialize(listing:, year:, quarter:, synthetic: false, latest_event: nil)
        @listing, @year, @quarter, @synthetic, @latest_event = listing, year, quarter, synthetic, latest_event
        @ticker = listing.split(":").last
        @event = nil
        @total_turns = nil
      end

      def call(name, arguments, result, forbidden: [])
        text = Agent.safe_text!(result.fetch("text"), forbidden: forbidden, bytes: 262_144)
        date = nil
        coverage = nil
        case name
        when "GetEarningsCallEvent"
          header = text.split("\n\n", 2).first
          ticker = field(header, "Ticker")
          period = field(header, "Fiscal period")
          id = field(header, "Event id")
          date = field(header, "Call date (UTC)")
          unless ticker == @ticker && period == "FY#{@year} Q#{@quarter}" &&
                 id&.match?(/\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/i) &&
                 date.is_a?(String) && date.match?(/\A\d{4}-\d{2}-\d{2}\z/) &&
                 field(header, "Status") == "Concluded"
            raise Research::Error.new("mcp_event_identity_unverified")
          end
          if @latest_event && (@latest_event["provider_event_id"] != id ||
              Date.iso8601(date) != Time.iso8601(@latest_event.fetch("event_at")).utc.to_date)
            raise Research::Error.new("latest_event_changed")
          end
          @event = { "id" => id, "date" => date, "transcript" => text.match?(/^- Transcript: available\b/) &&
            !text.match?(/presentation only|partial recording/i) }
        when "GetEarningsBrief"
          raise Research::Error.new("mcp_event_required") unless @event
          first, heading = text.lines.reject { |line| line.strip.empty? }.first(2).map(&:strip)
          unless first&.match?(/\A# #{Regexp.escape(@ticker)} (?:\u2014|-) earnings brief\z/) &&
                 heading&.match?(/\A## FY#{@year} Q#{@quarter} \(call #{Regexp.escape(@event.fetch('date'))}\)\z/) &&
                 text.scan(/^## FY\d{4} Q[1-4] /).size == 1
            raise Research::Error.new("mcp_brief_period_unverified")
          end
          date = @event.fetch("date")
        when "GetEarningsCallTranscript"
          raise Research::Error.new("mcp_transcript_unavailable_or_partial") unless @event && @event["transcript"]
          header = text.split("\n\n", 2).first
          range = field(header, "Turns")&.match(/\A(\d+)-(\d+) of (\d+)\z/)
          start, finish, total = range ? range.captures.map(&:to_i) : [0, 0, 0]
          unless header.lines.first&.match?(/\A# .+ Q#{@quarter} FY#{@year} Earnings Call (?:\u2014|-) speakers\s*\z/) &&
                 field(header, "Ticker") == @ticker && field(header, "Call date (UTC)") == @event["date"] &&
                 start == arguments.fetch("offset") + 1 && finish >= start &&
                 finish - start + 1 <= 50 && finish <= total && total.positive? &&
                 (@total_turns.nil? || @total_turns == total)
            raise Research::Error.new("mcp_transcript_page_unverified")
          end
          @total_turns = total
          date = @event.fetch("date")
          coverage = { "first_turn" => start, "last_turn" => finish, "total_turns" => total,
                       "complete_call" => start == 1 && finish == total }
        else
          raise Research::Error.new("agent_tool_not_authorized")
        end
        raise Research::Error.new("future_mcp_event") if Date.iso8601(date) > Time.current.utc.to_date
        { "source_id" => "mcp:#{Digest::SHA256.hexdigest(JSON.generate([name, arguments, text]))}",
          "origin" => @synthetic ? "fixture" : "live_mcp", "tool" => name, "content" => text,
          "listing_identity" => @listing, "fiscal_year" => @year, "fiscal_quarter" => @quarter,
          "provider_event_id" => @event["id"], "event_date" => date, "event_time_precision" => "date_only",
          "source_timezone" => "UTC", "published_at" => nil, "known_at" => nil,
          "received_at" => Time.current.utc.iso8601(6), "publication_unknown" => true,
          "coverage" => coverage, "synthetic" => @synthetic,
          "mcp_protocol_version" => result["protocol_version"],
          "citation_url" => @synthetic ? "https://example.invalid/research/alpha" : "https://equibles.com/stocks/#{@ticker}" }
      rescue KeyError, ArgumentError
        raise Research::Error.new("mcp_evidence_unverified"), cause: nil
      end

      private

      def field(header, label)
        values = header.lines.filter_map { |line| line.match(/\A- #{Regexp.escape(label)}: ([^\r\n]+)\s*\z/)&.captures&.first }
        values.size == 1 ? values.first.strip : nil
      end
    end
  end
end
