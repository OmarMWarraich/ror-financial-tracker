require "test_helper"

class MarketDashboardTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @previous_flag = ENV["MARKET_DASHBOARD_ENABLED"]
    ENV["MARKET_DASHBOARD_ENABLED"] = "1"
    @key = "eq_original_dashboard_fixture"
    @digest = Digest::SHA256.hexdigest(@key)
  end

  teardown do
    @previous_flag.nil? ? ENV.delete("MARKET_DASHBOARD_ENABLED") : ENV["MARKET_DASHBOARD_ENABLED"] = @previous_flag
    ResearchSourceUsage.where(key_digest: @digest).delete_all
  end

  test "seven bounded calls show delayed quotes and negative EPS without persisting market evidence" do
    requests = []
    before = [Stock.count, EquiblesConnection.count, ResearchDocument.count]
    with_provider(requests) do
      result = MarketDashboard.new(tickers: "aapl, msft, nvda", api_key: @key).call
      assert_equal 7, result[:requests]
      assert_empty result[:errors]
      assert_equal true, result[:stocks].first[:quote]["delayed"]
      assert_equal BigDecimal("-0.25"), result[:stocks].first[:earnings]["points"].first["value"]
      assert_equal before, [Stock.count, EquiblesConnection.count, ResearchDocument.count]
      assert_equal 7, ResearchSourceUsage.where(key_digest: @digest).sum(:requests_used)
      assert_equal 7, requests.size
    end
  end

  test "invalid inputs disabled feature and missing key never reach the provider" do
    Net::HTTP.stub(:start, ->(*) { flunk "Unexpected request" }) do
      [nil, "", "AAPL,,NVDA", "AAPL,AAPL", Array.new(11) { |i| "STOCK#{i}" }.join(","), "../AAPL"].each do |input|
        assert_raises(EquiblesClient::EvidenceError) { MarketDashboard.new(tickers: input, api_key: @key) }
      end
      assert_equal "missing_credentials", assert_raises(EquiblesClient::EvidenceError) {
        MarketDashboard.new(tickers: "AAPL", api_key: nil).call
      }.message
      assert_equal "invalid_credentials", assert_raises(EquiblesClient::EvidenceError) {
        MarketDashboard.new(tickers: "AAPL", api_key: "sk_original_wrong_provider").call
      }.message
      ENV["MARKET_DASHBOARD_ENABLED"] = "0"
      assert_equal "dashboard_disabled", assert_raises(EquiblesClient::EvidenceError) {
        MarketDashboard.new(tickers: "AAPL", api_key: @key).call
      }.message
    end
  end

  test "quota exhaustion stops before another HTTP exchange and retains consumed reservations" do
    ResearchSourceUsage.create!(key_digest: @digest, budget_date: Time.current.utc.to_date, requests_used: 119)
    requests = []
    with_provider(requests) do
      result = MarketDashboard.new(tickers: "AAPL,MSFT,NVDA", api_key: @key).call
      assert_equal 1, requests.size
      assert_nil result[:stocks].first[:quote]
      assert result[:errors].any? { |message| message.include?("Local quota") }
      assert_equal 120, ResearchSourceUsage.where(key_digest: @digest).sum(:requests_used)
    end
  end

  test "concurrent refreshes share the same atomic key allowance" do
    ResearchSourceUsage.create!(key_digest: @digest, budget_date: Time.current.utc.to_date, requests_used: 119)
    requests = []
    with_provider(requests) do
      results = 2.times.map do
        Thread.new do
          ApplicationRecord.connection_pool.with_connection do
            MarketDashboard.new(tickers: "AAPL", api_key: @key).call
          end
        end
      end.map(&:value)
      assert_equal 1, results.sum { |result| result[:requests] }
      assert_equal 1, requests.length
      assert_equal 120, ResearchSourceUsage.where(key_digest: @digest).sum(:requests_used)
    end
  end

  test "remote allowance exhaustion stops later exchanges" do
    requests = []
    with_provider(requests, remaining: "0") do
      result = MarketDashboard.new(tickers: "AAPL", api_key: @key).call
      assert_equal 1, requests.length
      assert_nil result[:stocks].first[:quote]
      assert result[:errors].any? { |message| message.include?("Provider quota") }
    end
  end

  test "operator flag cannot enable the dashboard in production" do
    Rails.stub(:env, ActiveSupport::StringInquirer.new("production")) do
      assert_not MarketDashboard.enabled?
    end
  end

  test "provider authentication and network failures are explicit with no synthetic substitute or retries" do
    [["403", nil], [nil, Net::ReadTimeout.new]].each do |status, failure|
      calls = 0
      Net::HTTP.stub(:start, ->(*, **, &block) {
        calls += 1
        raise failure if failure
        http = Object.new.tap { |http|
          http.define_singleton_method(:request) { |_request| Net::HTTPForbidden.new("1.1", status, "Forbidden") }
        }
        block.call(http)
      }) do
        result = MarketDashboard.new(tickers: "AAPL", api_key: @key).call
        assert_equal 1, calls
        assert_nil result[:stocks].first[:quote]
        assert_nil result[:stocks].first[:earnings]
        assert_not_empty result[:errors]
      end
    end
  end

  test "malformed earnings units identity and dates are rejected instead of fabricated figures" do
    %w[unit ticker filedDate].each do |field|
      requests = []
      with_provider(requests, invalid: field) do
        result = MarketDashboard.new(tickers: "AAPL", api_key: @key).call
        assert result[:stocks].first[:quote]
        assert_nil result[:stocks].first[:earnings]
        assert_not_empty result[:errors]
      end
    end
  end

  test "ranked ten stock view uses eight calls for five charts and quote refresh uses only one" do
    requests = []
    with_provider(requests) do
      result = MarketDashboard.new(api_key: @key).call(mode: "leaders")
      assert_equal 10, result[:stocks].size
      assert_equal 8, result[:requests]
      assert_equal 5, result[:stocks].count { |stock| stock[:history]&.[]("points")&.any? }
      assert_empty result[:errors]
      assert_equal 30, result[:selected][:history]["points"].size
      assert result[:selected][:earnings]["points"].any?
      symbols = result[:stocks].map { |stock| stock[:ticker] }.join(",")
      refresh = MarketDashboard.new(tickers: symbols, api_key: @key).call(mode: "quotes")
      assert_equal 1, refresh[:requests]
      assert_equal 10, refresh[:stocks].count { |stock| stock[:quote] }
      assert_nil refresh[:selected]
      assert_equal 9, ResearchSourceUsage.where(key_digest: @digest).sum(:requests_used)
    end
  end

  test "a bad batch quote cannot become a USD price and does not discard valid peers" do
    requests = []
    with_provider(requests, invalid: "quote_currency") do
      result = MarketDashboard.new(tickers: "ALPHA,BRAVO", api_key: @key).call(mode: "quotes")
      assert_nil result[:stocks].first[:quote]
      assert result[:stocks].last[:quote]
      assert result[:errors].any? { |error| error.include?("Unsupported currency") }
      assert_equal 1, requests.size
    end
  end

  test "rank order duplicate listings future bars and malformed OHLC are explicit failures" do
    %w[ranking duplicate future_date invalid_bar].each do |invalid|
      with_provider([], invalid: invalid) do
        result = MarketDashboard.new(api_key: @key).call(mode: "leaders")
        assert_not_empty result[:errors], invalid
        if %w[ranking duplicate].include?(invalid)
          assert_empty result[:stocks]
        else
          assert_nil result[:selected][:history]
        end
      end
    end
  end

  test "unknown modes never dispatch a provider request" do
    Net::HTTP.stub(:start, ->(*) { flunk "Unexpected request" }) do
      assert_raises(EquiblesClient::EvidenceError) { MarketDashboard.new(api_key: @key).call(mode: "trade") }
    end
  end

  test "server-side selection preserves the ranked universe without changing companies" do
    with_provider([]) do
      result = MarketDashboard.new(api_key: @key).call(mode: "leaders", selected_ticker: "BRAVO")
      assert_equal 10, result[:stocks].size
      assert_equal "BRAVO", result[:selected][:ticker]
      assert_equal "Original fixture BRAVO", result[:selected][:name]
      assert_equal 8, result[:requests]
    end
  end

  test "a stock outside the top ten loads the same profile history quote and earnings" do
    requests = []
    with_provider(requests) do
      result = MarketDashboard.new(tickers: "ZULU", api_key: @key).call(mode: "detail")
      assert_equal 4, result[:requests]
      assert_equal "Original fixture ZULU", result[:selected][:name]
      assert_equal 10_000_000_000, result[:selected][:market_cap]
      assert result[:selected][:quote]
      assert_equal 30, result[:selected][:history]["points"].size
      assert result[:selected][:earnings]["points"].any?
      assert_empty result[:errors]
      ranked = MarketDashboard.new(api_key: @key).call(mode: "leaders", selected_ticker: "ZULU")
      assert_equal 10, ranked[:stocks].size
      assert_equal "ZULU", ranked[:selected][:ticker]
      assert_equal "Original fixture ZULU", ranked[:selected][:name]
      assert_equal 10_000_000_000, ranked[:selected][:market_cap]
      assert_equal 11, ranked[:requests]
      assert_empty ranked[:errors]
      quotes = MarketDashboard.new(tickers: ranked[:stocks].map { |stock| stock[:ticker] }.join(","), api_key: @key)
        .call(mode: "quotes", selected_ticker: "ZULU")
      assert_equal 1, quotes[:requests]
      assert_equal 11, quotes[:stocks].size
      assert_equal "ZULU", quotes[:stocks].last[:ticker]
      assert quotes[:stocks].last[:quote]
    end
  end

  test "listing browsing shares the provider budget and stores no stock corpus" do
    before = Stock.count
    requests = []
    with_provider(requests) do
      page = MarketDashboard.new(api_key: @key).listings(query: "Zulu")
      assert_equal [{ ticker: "ZULU", name: "Original listing ZULU" }], page[:stocks]
      assert_equal 1, requests.size
      assert_equal 1, ResearchSourceUsage.where(key_digest: @digest).sum(:requests_used)
      assert_equal before, Stock.count
    end
    ResearchSourceUsage.create!(key_digest: @digest, budget_date: Time.current.utc.to_date, requests_used: 119)
    Net::HTTP.stub(:start, ->(*) { flunk "Quota exhausted listing request" }) do
      assert_equal "local_quota", assert_raises(EquiblesClient::EvidenceError) {
        MarketDashboard.new(api_key: @key).listings
      }.message
    end
  end

  private

  def with_provider(requests, invalid: nil, remaining: nil)
    http = Object.new
    http.define_singleton_method(:request) do |request|
      requests << request
      ticker = request.uri.path.split("/")[3]
      body = if request.uri.path.end_with?("/listings")
        query = URI.decode_www_form(request.uri.query).to_h
        symbols = %w[ALPHA BRAVO ZULU].select { |symbol| query["query"].to_s.empty? || symbol.downcase.include?(query["query"].downcase) }
        offset = query.fetch("offset").to_i
        rows = symbols.drop(offset).map { |symbol| { ticker: symbol, companyName: "Original listing #{symbol}", market: "US", currency: "USD" } }
        { data: rows, meta: { offset: offset, count: rows.size, hasMore: false } }
      elsif request.uri.path.end_with?("/screener/stocks")
        query = URI.decode_www_form(request.uri.query).to_h
        symbols = query["tickers"]&.split(",") || %w[ALPHA BRAVO CHARLIE DELTA ECHO FOXTROT GOLF HOTEL INDIA JULIET]
        rows = symbols.each_with_index.map { |symbol, index| { ticker: symbol, name: "Original fixture #{symbol}", sector: "Original sector", market: "US", currency: "USD", marketCap: (10 - index) * 1_000_000_000 } }
        rows.reverse! if invalid == "ranking"
        rows.last[:ticker] = rows.first[:ticker] if invalid == "duplicate"
        { data: rows }
      elsif request.uri.path.end_with?("/quotes")
        symbols = URI.decode_www_form(request.uri.query).to_h.fetch("tickers").split(",")
        rows = symbols.map { |symbol| { ticker: symbol, currency: "USD", price: 123.45, stale: false, delayed: true,
          asOf: 15.minutes.ago.utc.iso8601, sessionDate: Date.current.iso8601 } }
        rows.first[:currency] = "EUR" if invalid == "quote_currency"
        { data: rows }
      elsif request.uri.path.end_with?("/prices")
        rows = 30.times.map { |index| { date: (Time.current.utc.to_date - index - 1).iso8601,
          open: 100, high: 105, low: 95, close: 100 + index / 10.0, volume: 1000 } }
        rows.first[:date] = (Date.current + 1).iso8601 if invalid == "future_date"
        rows.first[:close] = 999 if invalid == "invalid_bar"
        { ticker: ticker, currency: "USD", data: rows, meta: { hasMore: false } }
      elsif request.uri.path.end_with?("/quote")
        { ticker: ticker, currency: "USD", price: 123.45, stale: false, delayed: true,
          asOf: 15.minutes.ago.utc.iso8601, sessionDate: Date.current.iso8601 }
      else
        data = { ticker: ticker, concept: "eps-diluted", unit: "USD/shares",
          quarterly: [{ fiscalPeriod: "2026Q3", value: -0.25, periodEnd: "2026-09-30", filedDate: "2026-10-30", splitBasis: "today" }] }
        data[:unit] = "EUR/shares" if invalid == "unit"
        data[:ticker] = "WRONG" if invalid == "ticker"
        data[:quarterly].first[:filedDate] = "2026-02-31" if invalid == "filedDate"
        data
      end
      response = Net::HTTPOK.new("1.1", "200", "OK")
      response["x-ratelimit-remaining"] = remaining if remaining
      json = JSON.generate(body)
      response.define_singleton_method(:body) { json }
      response
    end
    Net::HTTP.stub(:start, ->(*, **, &block) { block.call(http) }) { yield }
  end
end
