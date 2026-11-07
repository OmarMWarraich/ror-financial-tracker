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
      [nil, "", "AAPL,,NVDA", "AAPL,AAPL", "AAPL,MSFT,NVDA,SPY", "../AAPL"].each do |input|
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
    ResearchSourceUsage.create!(key_digest: @digest, budget_date: Time.current.utc.to_date, requests_used: 29)
    requests = []
    with_provider(requests) do
      result = MarketDashboard.new(tickers: "AAPL,MSFT,NVDA", api_key: @key).call
      assert_equal 1, requests.size
      assert_nil result[:stocks].first[:quote]
      assert result[:errors].any? { |message| message.include?("Local quota") }
      assert_equal 30, ResearchSourceUsage.where(key_digest: @digest).sum(:requests_used)
    end
  end

  test "concurrent refreshes share the same atomic key allowance" do
    ResearchSourceUsage.create!(key_digest: @digest, budget_date: Time.current.utc.to_date, requests_used: 29)
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
      assert_equal 30, ResearchSourceUsage.where(key_digest: @digest).sum(:requests_used)
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

  private

  def with_provider(requests, invalid: nil, remaining: nil)
    http = Object.new
    http.define_singleton_method(:request) do |request|
      requests << request
      ticker = request.uri.path.split("/")[3]
      body = if request.uri.path.end_with?("/screener/stocks")
        symbols = URI.decode_www_form(request.uri.query).to_h.fetch("tickers").split(",")
        { data: symbols.map { |symbol| { ticker: symbol, name: "Original fixture #{symbol}", sector: "Original sector" } } }
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
