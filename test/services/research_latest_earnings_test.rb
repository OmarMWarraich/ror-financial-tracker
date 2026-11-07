require "test_helper"

class ResearchLatestEarningsTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @event = { "id" => "00000000-0000-0000-0000-000000000003", "eventType" => "EarningsCall",
      "ticker" => "TEST", "fiscalYear" => 2026, "fiscalQuarter" => 3, "callDate" => "2026-10-28T20:00:00+02:00",
      "callDateIsPeriodEnd" => false, "isTombstoned" => false, "hasTranscript" => true,
      "partialRecording" => false, "presentationOnly" => false }
    @transport = Transport.new
    @reservations = 0
  end

  test "fixed REST listing includes uncaptured events then verifies the exact newest period" do
    future = @event.merge("id" => "00000000-0000-0000-0000-000000000004", "callDate" => "2027-01-28T18:00:00Z", "fiscalQuarter" => 4)
    result = resolve([future, @event])
    assert_equal 2026, result["fiscal_year"]
    assert_equal 3, result["fiscal_quarter"]
    assert_equal "2026-10-28T18:00:00.000000Z", result["event_at"]
    assert result["transcript_complete"]
    assert_equal 2, @reservations
    assert_not @transport.transaction_open
    assert_includes @transport.uris.first.query, "includeUncaptured=true"
    assert_equal "/v1/stocks/TEST/earnings-calls/2026/3", @transport.uris.last.path
  end

  test "a hidden placeholder or unknown latest date never falls back to an older call" do
    older = @event.merge("id" => "00000000-0000-0000-0000-000000000002", "callDate" => "2026-07-28T18:00:00Z", "fiscalQuarter" => 2)
    %w[isTombstoned callDateIsPeriodEnd].each do |flag|
      result = resolve([@event.merge(flag => true), older])
      assert_equal "latest_event_unconfirmed_or_unavailable", result["reason"]
      assert_equal 1, @reservations
    end
    result = resolve([@event.merge("callDate" => "2026-10-28"), older])
    assert_equal "latest_event_time_unknown", result["reason"]
    assert_equal "2026-10-28", result["unconfirmed_call_date"]
    assert_equal 1, @reservations
  end

  test "wrong identity ordering page counts and changing details are explicit failures" do
    older = @event.merge("id" => "00000000-0000-0000-0000-000000000002", "callDate" => "2026-07-28T18:00:00Z", "fiscalQuarter" => 2)
    assert_raises(Research::Error) { resolve([older, @event]) }
    assert_raises(Research::Error) { resolve([@event, @event]) }
    assert_raises(Research::Error) { resolve([@event.merge("fiscalQuarter" => 9)]) }
    assert_raises(Research::Error) { resolve([@event], detail: @event.merge("ticker" => "OTHER")) }
    assert_raises(Research::Error) { resolve([@event], detail: @event.merge("callDate" => "2026-10-29T18:00:00Z")) }
    assert_raises(Research::Error) { resolve([@event], meta: { "offset" => 1 }) }
  end

  test "bounded empty or future-only windows state absence or incomplete discovery" do
    assert_equal "latest_event_unavailable", resolve([])["reason"]
    future = @event.merge("callDate" => "2027-01-28T18:00:00Z")
    assert_equal "latest_event_window_exhausted", resolve([future], meta: { "hasMore" => true, "total" => 100 })["reason"]
    result = resolve([@event], detail: @event.merge("partialRecording" => true))
    assert_not result["transcript_complete"]
  end

  private

  def resolve(rows, detail: @event, meta: {})
    @reservations = 0
    @transport.responses = [{ "data" => rows, "meta" => { "limit" => 50, "offset" => 0, "count" => rows.size,
                                                        "hasMore" => false, "total" => rows.size }.merge(meta) }, detail]
    Research::LatestEarnings.new(transport: @transport).call(provider: "equibles", listing_identity: "US:TEST", api_key: "original-dummy",
      before_request: -> { @reservations += 1; 5.0 })
  end

  class Transport
    attr_accessor :responses
    attr_reader :uris, :transaction_open
    def initialize
      @uris = []
    end
    def call(uri:, **)
      @uris << uri
      @transaction_open = ApplicationRecord.connection.transaction_open?
      responses.shift
    end
  end
end
