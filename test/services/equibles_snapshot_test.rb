require_relative "equibles_client_test"

class EquiblesSnapshotTest < EquiblesClientTest
  def setup
    super
    @quote.merge!("asOf" => "2026-11-04T15:00:00Z", "sessionDate" => "2026-11-04",
                  "expectedSessionDate" => "2026-11-04")
    @received_at = Time.iso8601("2026-11-04T15:15:00Z")
  end

  def test_normalizes_source_and_received_times_without_claiming_realtime
    @quote["delayed"] = true
    raw = JSON.generate(@quote).sub(/"price":[^,}]+/, '"price":215.330123456789')
    with_responses(success_response(raw, raw: true)) do |requests|
      snapshot = @client.snapshot("aapl", received_at: @received_at)
      assert_equal "215.330123456789", snapshot["price"]
      assert_equal "2026-11-04T15:00:00.000000Z", snapshot["source_at"]
      assert_equal "2026-11-04T15:15:00.000000Z", snapshot["received_at"]
      assert_equal "delayed", snapshot["quality"]
      assert_equal false, snapshot["decision_eligible"]
      assert_equal 1, requests.length
    end
  end

  def test_unknown_source_time_is_never_filled_from_received_time
    @quote.delete("asOf")
    @quote.delete("delayed")
    with_responses(success_response(@quote)) do
      snapshot = @client.snapshot("AAPL", received_at: @received_at)
      assert_nil snapshot["source_at"]
      assert_nil snapshot["delayed"]
      assert_equal "unknown_source_time", snapshot["quality"]
    end
  end

  def test_rejects_bad_identity_currency_price_timing_and_sessions
    [
      ["ticker", "MSFT"], ["currency", "EUR"], ["price", "215.33"], ["price", 0],
      ["price", -1], ["stale", true], ["stale", nil], ["delayed", "false"],
      ["asOf", "tomorrow"], ["asOf", "2026-11-04T16:00:00Z"],
      ["sessionDate", "2026-02-31"], ["expectedSessionDate", []]
    ].each do |field, value|
      quote = @quote.merge(field => value)
      with_responses(success_response(quote)) do
        assert_raises(EquiblesClient::EvidenceError) { @client.snapshot("AAPL", received_at: @received_at) }
      end
    end
  end

  def test_class_share_identity_is_exact
    @quote["ticker"] = "BRK-B"
    with_responses(success_response(@quote)) do
      assert_equal "BRK-B", @client.snapshot("brk.b", received_at: @received_at)["instrument"]
    end
  end

  def test_http_and_transport_failures_are_safe_codes_without_retries
    { "429" => "provider_quota", "403" => "provider_authentication", "500" => "provider_unavailable" }.each do |status, code|
      response = Net::HTTPResponse::CODE_TO_OBJ.fetch(status).new("1.1", status, "Failed")
      with_responses(response) do
        error = assert_raises(EquiblesClient::EvidenceError) { @client.snapshot("AAPL") }
        assert_equal code, error.message
      end
    end
    Net::HTTP.stub(:start, ->(*) { raise Net::ReadTimeout }) do
      assert_equal "transport_failure", assert_raises(EquiblesClient::EvidenceError) { @client.snapshot("AAPL") }.message
    end
    with_responses(success_response("{", raw: true)) do
      assert_equal "malformed_response", assert_raises(EquiblesClient::EvidenceError) { @client.snapshot("AAPL") }.message
    end
  end
end
