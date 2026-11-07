require "test_helper"

class ResearchSourceTest < ActiveSupport::TestCase
  setup do
    @request = ResearchIngestion.new(provider: "equibles", source_kind: "earnings_transcript",
      listing_identity: "US:TEST", fiscal_year: 2026, fiscal_quarter: 3)
    @event = { "ticker" => "TEST", "id" => "00000000-0000-0000-0000-000000000001",
      "fiscalYear" => 2026, "fiscalQuarter" => 3, "callDate" => "2026-10-28T18:00:00Z",
      "callDateIsPeriodEnd" => false, "isTombstoned" => false, "hasTranscript" => true,
      "partialRecording" => false, "presentationOnly" => false, "transcriptDocumentId" => nil }
    @seen = []
    @reservations = 0
  end

  test "audio turns without document ID are accepted with exact identity and two bounded pages" do
    result = source([@event, page(50, total: 51), page(1, offset: 50, total: 51)])
    assert_equal 3, @reservations
    assert_equal 51, result[:parts].size
    assert_equal 50, result[:parts].last["turn_index"]
    assert_nil result[:known_at]
    assert_nil result[:published_at]
    assert result[:metadata]["known_available_unknown"]
    assert_equal Time.iso8601(@event["callDate"]), result[:event_at]
    assert @seen.all? { |call| call[:uri].host == "api.equibles.com" && call[:timeout] <= 5 }
    assert_includes @seen.last[:uri].query, "limit=50&offset=50"
  end

  test "wrong periods unavailable material and partial or summarized records fail closed" do
    [{ "ticker" => "OTHER" }, { "fiscalQuarter" => 2 }, { "isTombstoned" => true },
     { "hasTranscript" => false }, { "partialRecording" => true },
     { "presentationOnly" => true }].each do |change|
      assert_raises(Research::Error) { source([@event.merge(change)]) }
    end
    assert_raises(Research::Error) { source([@event, page(1).merge("isFiledRecord" => true)]) }
    assert_equal "transcript_pagination_limit", assert_raises(Research::Error) {
      source([@event, page(50, total: 101)])
    }.code
    assert_raises(Research::Error) { source([@event, page(1).merge("hasMore" => true)]) }
    assert_raises(Research::Error) { source([@event, page(1).merge("eventId" => "wrong-event")]) }
    backwards = page(1)
    backwards["data"][0].merge!("startSeconds" => 5, "endSeconds" => 2)
    assert_equal "invalid_source_time", assert_raises(Research::Error) { source([@event, backwards]) }.code
  end

  test "placeholder and unknown source dates never masquerade as known availability" do
    result = source([@event.merge("callDateIsPeriodEnd" => true), page(1)])
    assert_nil result[:event_at]
    assert_nil result[:known_at]
    assert result[:metadata]["call_date_is_period_end"]
  end

  test "briefs are exact-period only with named sections and no silent successor remapping" do
    @request.source_kind = "earnings_brief"
    brief = { "fiscalYear" => 2026, "fiscalQuarter" => 3, "callDate" => @event["callDate"],
      "tldr" => "Original synthetic brief.", "bullish" => ["Original demonstration upside."],
      "bearish" => ["Original demonstration risk."],
      "quotes" => [{ "text" => "Original quotation.", "speakerName" => "Fictional executive", "startSeconds" => 1 }] }
    response = { "data" => [brief] }
    result = source([@event, response])
    assert_equal %w[tldr bullish bearish quote], result[:parts].map { |part| part["section"] }
    assert_equal "Fictional executive", result[:parts].last["speaker"]
    comparisons = brief.merge("narrativeShift" => { "summary" => "Original shift." },
                              "guidanceComparison" => { "summary" => "Original guidance." })
    full = source([@event, { "data" => [comparisons] }])
    assert_equal %w[narrativeShift guidanceComparison], full[:parts].last(2).map { |part| part["section"] }
    assert_equal({ "summary" => "Original shift." }, JSON.parse(full[:parts][-2]["text"]))
    assert_raises(Research::Error) { source([@event, { "data" => [brief.merge("fiscalQuarter" => 2)] }]) }
    assert_raises(Research::Error) { source([@event, response.merge("listingNotice" => { "status" => "renamed" })]) }
  end

  test "transport rejects redirects malformed JSON content types and oversized bodies without retries" do
    http = FakeHTTP.new
    uri = URI("https://api.equibles.com/v1/stocks/TEST")
    Net::HTTP.stub(:new, http) do
      assert_equal({ "data" => [] }, Research::EquiblesTransport.new.call(uri: uri, api_key: "original-dummy", timeout: 1))
      assert_equal 0, http.max_retries
      [[302, "{}", "application/json", "source_http_error"],
       [403, "private-error", "text/html", "source_access_denied"],
       [200, "not-json", "application/json", "invalid_source_response"],
       [200, "{}", "text/html", "invalid_source_response"],
       [200, "a" * (Research::Chunker::MAX_BYTES + 1), "application/json", "source_too_large"]].each do |code, body, type, expected|
        http.response = Response.new(code.to_s, body, type)
        assert_equal expected, assert_raises(Research::Error) {
          Research::EquiblesTransport.new.call(uri: uri, api_key: "original-dummy", timeout: 1)
        }.code
      end
    end
    assert_raises(Research::Error) {
      Research::EquiblesTransport.new.call(uri: URI("https://other.test/"), api_key: "original-dummy", timeout: 1)
    }
  end

  private

  def source(responses)
    transport = lambda do |**arguments|
      @seen << arguments
      responses.shift || raise(Research::Error.new("unexpected_request"))
    end
    Research::EquiblesSource.new(transport: transport).call(@request, api_key: "original-dummy",
      before_request: -> { @reservations += 1; 5 })
  end

  def page(count, offset: 0, total: count)
    @event.slice("ticker", "fiscalYear", "fiscalQuarter", "callDate").merge(
      "eventId" => @event["id"], "isFiledRecord" => false, "offset" => offset,
      "turnCount" => count, "totalTurnCount" => total, "hasMore" => offset + count < total,
      "data" => Array.new(count) { { "speakerIndex" => 0, "speakerName" => "Fictional speaker",
                                    "text" => "Original demonstration speaker turn." } })
  end

  Response = Struct.new(:code, :body, :type) do
    def [](key) = key == "content-type" ? type : nil
    def read_body
      yield body
    end
  end

  class FakeHTTP
    attr_accessor :use_ssl, :open_timeout, :read_timeout, :write_timeout, :max_retries, :response
    def initialize
      @response = Response.new("200", '{"data":[]}', "application/json")
    end
    def request(_request)
      yield response
    end
  end
end
