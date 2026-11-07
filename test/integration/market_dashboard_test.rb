require "test_helper"

class MarketDashboardIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    @previous_flag = ENV["MARKET_DASHBOARD_ENABLED"]
    ENV["MARKET_DASHBOARD_ENABLED"] = "1"
    host! "localhost"
    https!
    sign_in users(:one)
  end

  teardown do
    @previous_flag.nil? ? ENV.delete("MARKET_DASHBOARD_ENABLED") : ENV["MARKET_DASHBOARD_ENABLED"] = @previous_flag
  end

  test "GET is private no-store and never consumes provider requests" do
    Net::HTTP.stub(:start, ->(*) { flunk "GET must not fetch" }) do
      get market_dashboard_path
      assert_response :success
      assert_equal "no-store", response.headers["Cache-Control"]
      assert_select 'form[data-turbo="false"]'
      assert_select '[data-testid="market-price"]', count: 0
      sign_out users(:one)
      post refresh_market_dashboard_path, params: { tickers: "AAPL" }
      assert_redirected_to new_user_session_path
    end
  end

  test "disabled and non-local access cannot use the operator credential" do
    Net::HTTP.stub(:start, ->(*) { flunk "Denied request must not fetch" }) do
      ENV["MARKET_DASHBOARD_ENABLED"] = "0"
      get market_dashboard_path
      assert_response :not_found
      ENV["MARKET_DASHBOARD_ENABLED"] = "1"
      host! "example.org"
      sign_in users(:one)
      post refresh_market_dashboard_path, params: { tickers: "AAPL" }
      assert_response :forbidden
    end
  end

  test "real-data shape renders prices earnings provenance and escaped company text" do
    result = { received_at: Time.current.utc, requests: 3, errors: [], stocks: [
      { ticker: "AAPL", name: "<script>bad()</script>", sector: nil,
        quote: { "price" => "123.45", "delayed" => true, "source_at" => "2026-11-06T19:00:00Z",
          "session" => { "sessionDate" => "2026-11-06" } },
        earnings: { "unit" => "USD/shares", "coverage_note" => "", "points" => [
          { "value" => -0.25, "periodEnd" => "2026-09-30", "filedDate" => "2026-10-30",
            "fiscalPeriod" => "2026Q3", "splitBasis" => "today" }
        ] } }
    ] }
    service = Object.new
    service.define_singleton_method(:call) { result }
    MarketDashboard.stub(:new, ->(*) { service }) do
      post refresh_market_dashboard_path, params: { tickers: "AAPL" }
      assert_response :success
      assert_select '[data-testid="market-price"]', text: "$123.45"
      assert_select '[data-testid="market-eps"]', text: "-$0.25"
      assert_includes response.body, "Delayed quote"
      assert_includes response.body, "latest restatements"
      assert_not_includes response.body, "<script>bad()</script>"
    end
  end
end
