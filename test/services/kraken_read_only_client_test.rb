require "minitest/autorun"
require "minitest/mock"
require_relative "../../app/services/kraken_read_only_client"

class KrakenReadOnlyClientTest < Minitest::Test
  def setup
    @nonce = 100
    @client = KrakenReadOnlyClient.new(api_key: "testAPIkey000", api_secret: Base64.strict_encode64("s" * 32),
                                       nonce: -> { @nonce += 1 })
    @info = { "permissions" => ["query-funds"], "iban" => "AA88 TEST ACCOUNT", "valid_until" => "0" }
  end

  def test_inspects_permissions_before_any_balances_and_signs_only_allowlisted_reads
    with_responses(@info, { "XXBT" => "0.001", "AAPL.T" => "2.50" }) do |requests|
      assert_equal ["query-funds"], @client.key_info(include_history: false)[:permissions]
      balances = @client.balances
      assert_equal ["XXBT", "AAPL.T"], balances.map { |row| row["provider_instrument_id"] }
      assert_equal "2.5", balances.last["quantity"]
      assert balances.none? { |row| row["analytics_supported"] }
      assert_equal ["/0/private/GetApiKeyInfo", "/0/private/Balance"], requests.map(&:path)
      requests.each do |request|
        nonce = URI.decode_www_form(request.body).to_h.fetch("nonce")
        expected = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA512", "s" * 32,
          request.path + OpenSSL::Digest::SHA256.digest(nonce + request.body)))
        assert_equal expected, request["API-Sign"]
        assert_equal "testAPIkey000", request["API-Key"]
        assert_instance_of Net::HTTP::Post, request
        refute_includes request.path, "testAPIkey000"
      end
      assert_operator URI.decode_www_form(requests.last.body).to_h.fetch("nonce").to_i, :>,
                      URI.decode_www_form(requests.first.body).to_h.fetch("nonce").to_i
    end
    refute @client.respond_to?(:request)
    assert_equal %i[key_info balances trades], KrakenReadOnlyClient::PATHS.keys
  end

  def test_rejects_all_extra_permissions_and_unverifiable_metadata
    %w[modify-trades close-trades add-funds withdraw-funds earn-funds query-ledger
       create-ws-token export-data add-withdraw-address query-open-trades unknown].each do |scope|
      with_responses(@info.merge("permissions" => ["query-funds", scope])) do
        assert_raises(KrakenReadOnlyClient::PermissionError) { @client.key_info(include_history: false) }
      end
    end
    [nil, [], ["query-funds", "query-funds"], "query-funds"].each do |scopes|
      with_responses(@info.merge("permissions" => scopes)) do
        assert_raises(KrakenReadOnlyClient::PermissionError) { @client.key_info(include_history: false) }
      end
    end
    [{ "iban" => nil }, { "valid_until" => nil }, { "valid_until" => "bad" }].each do |change|
      with_responses(@info.merge(change)) do
        assert_raises(KrakenReadOnlyClient::PermissionError) { @client.key_info(include_history: false) }
      end
    end
    with_responses(@info.merge("valid_until" => "1")) do
      assert_raises(KrakenReadOnlyClient::RevokedError) { @client.key_info(include_history: false) }
    end
  end

  def test_optional_history_requires_exact_read_scope_and_normalizes_source_time
    info = @info.merge("permissions" => %w[query-funds query-closed-trades])
    trades = { "trades" => { "private-trade-id" => {
      "pair" => "XXBTZUSD", "type" => "buy", "price" => "100.25", "vol" => "0.01",
      "cost" => "1.0025", "fee" => "0.001", "time" => 1_700_000_000.0
    } } }
    with_responses(info, trades) do |requests|
      @client.key_info(include_history: true)
      result = @client.trades
      assert_equal "2023-11-14T22:13:20Z", result.first["source_time"]
      assert_equal "XXBTZUSD", result.first["provider_instrument_id"]
      refute result.first.key?("id")
      assert_equal "0", URI.decode_www_form(requests.last.body).to_h["ofs"]
    end
    with_responses(@info) do
      assert_raises(KrakenReadOnlyClient::PermissionError) { @client.key_info(include_history: true) }
    end
  end

  def test_malformed_balances_and_history_are_errors_not_empty_accounts
    [{ "XBT" => "-1" }, { "XBT" => 1.0 }, { "XBT" => "NaN" }, { "../asset" => "1" }].each do |balances|
      with_responses(balances) { assert_raises(KrakenReadOnlyClient::Error) { @client.balances } }
    end
    [{}, { "trades" => [] }, { "trades" => { "x" => nil } }].each do |history|
      with_responses(history) { assert_raises(KrakenReadOnlyClient::Error) { @client.trades } }
    end
  end

  def test_transport_quota_invalid_json_and_revocation_are_explicit_errors
    Net::HTTP.stub(:start, ->(*) { raise Net::ReadTimeout }) do
      assert_raises(KrakenReadOnlyClient::Error) { @client.balances }
    end
    [response("429", "{}"), response("503", "{}"), response("302", "{}"),
     response("200", "not-json"), response("200", JSON.generate("error" => [], "result" => []))].each do |reply|
      with_http(reply) { assert_raises(KrakenReadOnlyClient::Error) { @client.balances } }
    end
    with_http(response("200", JSON.generate("error" => ["EAPI:Invalid key"]))) do
      assert_raises(KrakenReadOnlyClient::RevokedError) { @client.balances }
    end
  end

  def test_invalid_key_material_is_rejected_without_transport
    [nil, "", "injected\nheader"].each do |key|
      assert_raises(KrakenReadOnlyClient::Error) do
        KrakenReadOnlyClient.new(api_key: key, api_secret: "bad", nonce: -> { 1 })
      end
    end
  end

  private

  def response(code, body)
    result = Net::HTTPResponse::CODE_TO_OBJ.fetch(code).new("1.1", code, "Test")
    result.define_singleton_method(:body) { body }
    result
  end

  def with_responses(*results)
    replies = results.map { |result| response("200", JSON.generate("error" => [], "result" => result)) }
    with_http(*replies) { |requests| yield requests }
  end

  def with_http(*replies)
    requests = []
    transport = Object.new
    transport.define_singleton_method(:request) do |request|
      requests << request
      replies.shift || raise("Unexpected additional request")
    end
    start = ->(host, port, **options, &block) do
      assert_equal "api.kraken.com", host
      assert_equal 443, port
      assert_equal({ use_ssl: true, open_timeout: 5, read_timeout: 5, write_timeout: 5, max_retries: 0 }, options)
      block.call(transport)
    end
    Net::HTTP.stub(:start, start) { yield requests }
    assert_empty replies
  end
end
