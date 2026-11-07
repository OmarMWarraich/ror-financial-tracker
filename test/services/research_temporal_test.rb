require "test_helper"

class ResearchTemporalTest < ActiveSupport::TestCase
  test "date-only placeholder and unknown times retain their basis without receipt substitution" do
    now = Time.current
    %w[2026-10-28 2026-10-28T18:00:00].each do |raw|
      result = Research::TemporalEvidence.source(
        { metadata: { "raw_call_date" => raw, "call_date_is_period_end" => false }, received_at: now }, provider: "equibles")
      assert_nil result[:values][:event_at]
      assert_nil result[:values][:known_at]
      assert_equal raw, result[:metadata]["event_at"]["raw"]
      assert_equal "unknown", result[:metadata]["known_at"]["confidence"]
      assert_equal "application_receipt", result[:metadata]["received_at"]["basis"]
      assert_not result[:fingerprint].key?("received_at")
    end
    result = Research::TemporalEvidence.source(
      { metadata: { "raw_call_date" => "2026-09-30", "call_date_is_period_end" => true }, received_at: now }, provider: "equibles")
    assert_equal "fiscal_period_placeholder", result[:metadata]["event_at"]["basis"]
  end

  test "confirmed offsets survive provenance while values serialize as UTC instants" do
    value = Time.iso8601("2026-10-28T19:00:00+02:00")
    result = Research::TemporalEvidence.source(
      { metadata: {}, received_at: Time.current, published_at: value, known_at: value }, provider: "synthetic")
    assert_equal "+02:00", result[:metadata]["known_at"]["zone"]
    revision = ResearchRevision.new(temporal_metadata: result[:metadata], known_at: value)
    assert_equal "2026-10-28T17:00:00.000000Z", Research::TemporalEvidence.describe(revision)["known_at"]["value"]
    assert_equal "unknown", Research::TemporalEvidence.describe(revision)["indexed_at"]["confidence"]
    assert_raises(Research::Error) {
      Research::TemporalEvidence.source({ metadata: {}, known_at: Date.today }, provider: "synthetic")
    }
  end

  test "source relevance and deletion are distinct type-specific policies" do
    now = Time.current
    policy = Research::TemporalPolicy
    assert policy.fresh?("quote", now: now, event_at: now - 119.seconds, fresh_until: now + 1.day)
    assert_not policy.fresh?("quote", now: now, event_at: now - 120.seconds, fresh_until: now + 1.day)
    assert_not policy.fresh?("quote", now: now, event_at: now + 1.second, fresh_until: now + 1.day)
    assert policy.fresh?("latest_earnings", now: now, event_at: now - 1.year, fresh_until: nil, latest_observed_at: now - 899.seconds)
    assert_not policy.fresh?("latest_earnings", now: now, event_at: now, fresh_until: now + 1.day, latest_observed_at: now - 900.seconds)
    %w[filing company_fact].each { |kind| assert policy.fresh?(kind, now: now, event_at: now - 10.years, fresh_until: nil) }
    assert_not policy.fresh?("earnings_transcript", now: now, event_at: now, fresh_until: now)
    assert_raises(Research::Error) { policy.fresh?("arbitrary", now: now, event_at: now, fresh_until: nil) }
  end
end
