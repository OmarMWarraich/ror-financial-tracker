require "minitest/autorun"
require "minitest/mock"
require_relative "../../app/services/equibles_client"

class EquiblesClientTest < Minitest::Test
  def setup
    @client = EquiblesClient.new(api_key: "eq_test_key")
    @quote = { "ticker" => "AAPL", "currency" => "USD", "price" => 215.3301,
               "stale" => false, "delayed" => false }
    @profile = { "data" => [{ "ticker" => "AAPL", "name" => "Apple Inc.", "price" => 200 }] }
  end

  def test_maps_paid_quote_price_instead_of_screener_price
    with_responses(success_response(@quote), success_response(@profile)) do |requests|
      assert_equal({ ticker: "AAPL", name: "Apple Inc.", last_price: BigDecimal("215.3301") },
                   @client.lookup(" aapl "))
      assert_equal ["/v1/stocks/AAPL/quote", "/v1/screener/stocks"], requests.map { |request| request.uri.path }
      assert_equal({ "tickers" => "AAPL", "limit" => "1" }, URI.decode_www_form(requests.last.uri.query).to_h)
    end
  end

  def test_accepts_plus_plan_delayed_quotes
    @quote["delayed"] = true
    with_responses(success_response(@quote), success_response(@profile)) do
      assert_equal BigDecimal("215.3301"), @client.lookup("AAPL")[:last_price]
    end
  end

  def test_preserves_class_share_quote_identity_when_screener_resolves_to_issuer
    @quote["ticker"] = "BRK-B"
    @profile["data"] = [{ "ticker" => "BRK-A", "name" => "Berkshire Hathaway" }]
    with_responses(success_response(@quote), success_response(@profile)) do |requests|
      assert_equal "BRK-B", @client.lookup("brk.b")[:ticker]
      assert_equal "/v1/stocks/BRK-B/quote", requests.first.uri.path
    end
  end

  def test_invalid_symbols_and_keys_do_not_make_requests
    Net::HTTP.stub(:start, ->(*) { flunk "Unexpected network request" }) do
      [nil, "", " ", "AAPL,MSFT", "../AAPL", "AAPL?key=secret", "A" * 33].each do |ticker|
        assert_nil @client.lookup(ticker)
      end
      [nil, "", " ", "eq_key\nheader"].each do |key|
        assert_nil EquiblesClient.new(api_key: key).lookup("AAPL")
      end
    end
  end

  def test_http_failures_return_nil_without_following_redirects_or_retrying
    { Net::HTTPBadRequest => "400", Net::HTTPUnauthorized => "401", Net::HTTPForbidden => "403",
      Net::HTTPNotFound => "404", Net::HTTPTooManyRequests => "429", Net::HTTPInternalServerError => "500",
      Net::HTTPServiceUnavailable => "503", Net::HTTPFound => "302" }.each do |response_class, code|
      with_responses(response_class.new("1.1", code, "Failure")) { assert_nil @client.lookup("AAPL") }
    end
  end

  def test_invalid_quotes_return_nil_before_company_lookup
    [@quote.merge("stale" => true), @quote.reject { |key, _| key == "stale" },
     @quote.merge("ticker" => "MSFT"), @quote.merge("currency" => "CAD"),
     @quote.merge("price" => nil), @quote.merge("price" => "unknown"),
     @quote.merge("price" => 0), @quote.merge("price" => -1), {}, nil, []].each do |quote|
      with_responses(success_response(quote)) { assert_nil @client.lookup("AAPL") }
    end
    with_responses(success_response("not JSON", raw: true)) { assert_nil @client.lookup("AAPL") }
    with_responses(success_response(nil, raw: true)) { assert_nil @client.lookup("AAPL") }
  end

  def test_missing_company_name_or_failed_profile_returns_nil
    [{}, { "data" => nil }, { "data" => [] }, { "data" => [nil] },
     { "data" => [{ "name" => " " }] }, { "data" => [{ "name" => 123 }] }].each do |profile|
      with_responses(success_response(@quote), success_response(profile)) { assert_nil @client.lookup("AAPL") }
    end
    with_responses(success_response(@quote), Net::HTTPTooManyRequests.new("1.1", "429", "Limited")) do
      assert_nil @client.lookup("AAPL")
    end
  end

  def test_transport_failures_return_nil
    [Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNRESET,
     OpenSSL::SSL::SSLError, EOFError, Net::HTTPBadResponse].each do |error_class|
      Net::HTTP.stub(:start, ->(*) { raise error_class, "Request failed" }) do
        assert_nil @client.lookup("AAPL")
      end
    end
  end

  def test_listing_browse_and_search_use_provider_pagination_without_combining_market_and_query
    listing = { ticker: "ZULU", companyName: "Original Zulu Company", market: "US", currency: "USD", exchangeTradedProduct: false }
    page = { data: [listing], meta: { offset: 0, count: 1, hasMore: true } }
    with_responses(success_response(page)) do |requests|
      assert_equal({ stocks: [{ ticker: "ZULU", name: "Original Zulu Company" }], next_offset: 1 }, @client.listings)
      assert_equal "/v1/listings", requests.first.uri.path
      assert_equal({ "market" => "US", "limit" => "50", "offset" => "0" }, URI.decode_www_form(requests.first.uri.query).to_h)
    end
    page[:meta] = { offset: 50, count: 1, hasMore: false }
    with_responses(success_response(page)) do |requests|
      assert_nil @client.listings(query: "Zulu", offset: 50)[:next_offset]
      assert_equal({ "query" => "Zulu", "limit" => "50", "offset" => "50" }, URI.decode_www_form(requests.first.uri.query).to_h)
    end
  end

  def test_listing_search_excludes_other_currencies_and_funds_and_keeps_optional_names
    page = { data: [
      { ticker: "XETR:ZULU", companyName: "Original International", market: "DE", currency: "EUR" },
      { ticker: "FUND", companyName: "Original Fund", market: "US", currency: "USD", exchangeTradedProduct: true },
      { ticker: "ZULU", companyName: nil, market: "US", currency: "USD", exchangeTradedProduct: false }
    ], meta: { offset: 0, count: 3, hasMore: false } }
    with_responses(success_response(page)) do
      assert_equal [{ ticker: "ZULU", name: nil }], @client.listings(query: "Zulu")[:stocks]
    end
  end

  def test_invalid_listing_inputs_never_dispatch
    Net::HTTP.stub(:start, ->(*) { flunk "Unexpected listing request" }) do
      [nil, [], "A" * 81, "bad\nquery"].each do |query|
        assert_raises(EquiblesClient::EvidenceError) { @client.listings(query: query) }
      end
      [-1, "50", 1_000_001].each do |offset|
        assert_raises(EquiblesClient::EvidenceError) { @client.listings(offset: offset) }
      end
    end
  end

  def test_malformed_listing_metadata_identity_and_currency_are_explicit_errors
    row = { ticker: "ZULU", companyName: "Original Zulu", market: "US", currency: "USD" }
    [
      { data: [row], meta: { offset: 1, count: 1, hasMore: false } },
      { data: [], meta: { offset: 0, count: 0, hasMore: true } },
      { data: [row, row], meta: { offset: 0, count: 2, hasMore: false } },
      { data: [row.merge(currency: "EUR")], meta: { offset: 0, count: 1, hasMore: false } }
    ].each do |page|
      with_responses(success_response(page)) { assert_raises(EquiblesClient::EvidenceError) { @client.listings } }
    end
  end

  private

  def success_response(payload, raw: false)
    body = raw ? payload : JSON.generate(payload)
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.define_singleton_method(:body) { body }
    response
  end

  def with_responses(*responses)
    requests = []
    transport = Object.new
    transport.define_singleton_method(:request) do |request|
      requests << request
      responses.shift or raise "Unexpected extra request"
    end
    start = lambda do |host, port, **options, &block|
      assert_equal "api.equibles.com", host
      assert_equal 443, port
      assert_equal({ use_ssl: true, open_timeout: 5, read_timeout: 5, max_retries: 0 }, options)
      block.call(transport)
    end
    Net::HTTP.stub(:start, start) { yield requests }
    requests.each do |request|
      assert_equal "Bearer eq_test_key", request["Authorization"]
      assert_equal "application/json", request["Accept"]
      refute_includes request.uri.to_s, "eq_test_key"
    end
    assert_empty responses
  end
end