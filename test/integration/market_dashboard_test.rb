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

  test "root redirects guests to live charts without reading owner preferences" do
    sign_out users(:one)
    stock = { ticker: "ALPHA", name: "Original Alpha", quote: { "price" => "12", "delayed" => true },
      history: { "points" => [{ "date" => "2026-11-05", "close" => 10 },
        { "date" => "2026-11-06", "close" => 12 }] } }
    service = Object.new
    service.define_singleton_method(:call) do |mode:|
      raise "Wrong mode" unless mode == "leaders"
      { received_at: Time.current.utc, stocks: [stock], selected: stock, errors: [] }
    end
    MarketDashboard.stub(:new, ->(*) { service }) do
      DashboardPreferences.stub(:new, ->(*) { flunk "Guest must not read owner preferences" }) do
        get root_path
        assert_redirected_to dashboard_path
        follow_redirect!
        assert_response :success
        assert_equal "no-store", response.headers["Cache-Control"]
        assert_select "h1", text: "Dashboard"
        assert_select '[data-market-dashboard-enabled-value="true"]'
        assert_select 'button[type="submit"][disabled]', count: 0
        assert_select '[data-testid="market-price"]', text: "$12.00"
        assert_select '[data-market-color] svg', count: 4
        assert_select '[data-owner-scope]', count: 0
        assert_select '[data-preferences-url]', count: 0
        assert_select 'input[role="combobox"][aria-controls="dashboard-stock-options"]'
        assert_select '[data-controller="stock-picker"]'
        assert_not_includes response.body, "Sign in to load provider data"
        get market_dashboard_path
        assert_response :success
        host! "example.org"
        get dashboard_path
        assert_response :forbidden
      end
    end
  end

  test "disabled guest dashboard denies refresh while preferences remain authenticated" do
    sign_out users(:one)
    ENV["MARKET_DASHBOARD_ENABLED"] = "0"
    get dashboard_path
    assert_response :success
    assert_includes response.body, "Provider data is disabled"
    post refresh_market_dashboard_path, params: { mode: "leaders" }
    assert_response :not_found
    get dashboard_preferences_path, as: :json
    assert_response :unauthorized
    put dashboard_preferences_path, params: { preferences: { version: 1, selected: nil, ranges: {} } }, as: :json
    assert_response :unauthorized
  end

  test "sign in preserves an explicitly requested protected destination" do
    sign_out users(:one)
    get my_portfolio_path
    assert_redirected_to new_user_session_path
    user = users(:one)
    user.update!(password: "Original-dashboard-login-123", password_confirmation: "Original-dashboard-login-123")
    post user_session_path, params: { user: { email: user.email, password: "Original-dashboard-login-123" } }
    assert_redirected_to my_portfolio_path
  end

  test "non-JavaScript selection keeps the top ten view instead of calling it a one-stock ranking" do
    sign_out users(:one)
    service = Object.new
    service.define_singleton_method(:call) do |mode:, selected_ticker:|
      raise "Wrong selection" unless mode == "leaders" && selected_ticker == "BRAVO"
      { received_at: Time.current.utc, requests: 4, errors: [], stocks: [], selected: nil }
    end
    MarketDashboard.stub(:new, ->(*) { service }) do
      post refresh_market_dashboard_path, params: { mode: "detail", tickers: "BRAVO" }
      assert_response :success
      assert_select '[data-owner-scope]', count: 0
    end
  end

  test "GET is private no-store and loads the dashboard before browser rendering" do
    service = Object.new
    service.define_singleton_method(:call) { |mode:| raise "Wrong mode" unless mode == "leaders"; { received_at: Time.current.utc, stocks: [], errors: [], selected: nil } }
    MarketDashboard.stub(:new, ->(*) { service }) do
      Net::HTTP.stub(:start, ->(*) { flunk "Unstubbed provider request" }) do
        get dashboard_path
        assert_response :success
        assert_equal "no-store", response.headers["Cache-Control"]
        assert_select 'form[data-turbo="false"]'
        assert_select '[data-testid="market-price"]', count: 0
        sign_out users(:one)
        post refresh_market_dashboard_path, params: { mode: "leaders" }
        assert_response :success
      end
    end
  end

  test "disabled and non-local access cannot use the operator credential" do
    Net::HTTP.stub(:start, ->(*) { flunk "Denied request must not fetch" }) do
      ENV["MARKET_DASHBOARD_ENABLED"] = "0"
      get dashboard_path
      assert_response :success
      assert_includes response.body, "Provider data is disabled"
      post refresh_market_dashboard_path, params: { mode: "leaders" }
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

  test "JSON refresh is public and returns quotes without a full financial reload" do
    sign_out users(:one)
    result = { received_at: Time.current.utc, requests: 1, errors: [], stocks: [], selected: nil }
    service = Object.new
    service.define_singleton_method(:call) { |mode:| raise "Wrong mode" unless mode == "quotes"; result }
    MarketDashboard.stub(:new, ->(*) { service }) do
      post refresh_market_dashboard_path, params: { mode: "quotes", tickers: "ALPHA" }, as: :json
      assert_response :success
      assert_equal 1, response.parsed_body["requests"]
      assert_nil response.parsed_body["selected"]
      assert_equal "no-store", response.headers["Cache-Control"]
    end
  end

  test "guests can search paged listings and provider text remains escaped" do
    sign_out users(:one)
    service = Object.new
    service.define_singleton_method(:listings) do |query:, offset:|
      raise "Wrong listing parameters" unless query == "Zulu" && offset == 50
      { stocks: [{ ticker: "ZULU", name: "<script>original</script>" }], next_offset: 100 }
    end
    MarketDashboard.stub(:new, ->(*) { service }) do
      get dashboard_listings_path, params: { query: "Zulu", offset: 50 }, as: :json
      assert_response :success
      assert_equal "no-store", response.headers["Cache-Control"]
      assert_equal 100, response.parsed_body["next_offset"]
      assert_includes response.parsed_body["html"], "data-stock-picker-ticker=\"ZULU\""
      assert_not_includes response.parsed_body["html"], "<script>"
      get dashboard_listings_path, params: { query: "Zulu", offset: 50 }
      assert_response :success
      assert_select 'a[href="/dashboard?selected=ZULU"]'
      assert_select 'a[href*="offset=100"]', text: "Next page"
    end
  end

  test "listing errors and feature transport gates are explicit for guests" do
    sign_out users(:one)
    Net::HTTP.stub(:start, ->(*) { flunk "Invalid or denied search must not fetch" }) do
      get dashboard_listings_path, params: { offset: "-1" }, as: :json
      assert_response :unprocessable_entity
      assert_equal "Invalid listing search", response.parsed_body["error"]
      get dashboard_listings_path, params: { query: "A" * 81 }, as: :json
      assert_response :unprocessable_entity
      ENV["MARKET_DASHBOARD_ENABLED"] = "0"
      get dashboard_listings_path, as: :json
      assert_response :not_found
      ENV["MARKET_DASHBOARD_ENABLED"] = "1"
      host! "example.org"
      get dashboard_listings_path, as: :json
      assert_response :forbidden
    end
  end

  test "an arbitrary selected symbol survives guest GET and quote refresh" do
    sign_out users(:one)
    service = Object.new
    modes = []
    service.define_singleton_method(:call) do |mode:, selected_ticker:|
      raise "Wrong selected ticker" unless selected_ticker == "ZULU"
      modes << mode
      { received_at: Time.current.utc, requests: 1, errors: [], stocks: [], selected: nil }
    end
    MarketDashboard.stub(:new, ->(*) { service }) do
      get dashboard_path, params: { selected: "ZULU" }
      assert_response :success
      post refresh_market_dashboard_path, params: { mode: "quotes", tickers: "ALPHA", selected: "ZULU" }, as: :json
      assert_response :success
      assert_equal %w[leaders quotes], modes
    end
  end

  test "chart renders only actual bounded daily bars with accessible range controls" do
    stock = { ticker: "ALPHA", name: "Original Alpha", quote: { "price" => "10", "delayed" => true },
      history: { "points" => [{ "date" => "2026-11-05", "close" => 10, "open" => 9, "high" => 11, "low" => 8 },
        { "date" => "2026-11-06", "close" => 12, "open" => 11, "high" => 13, "low" => 10 }] } }
    result = { received_at: Time.current.utc, requests: 4, errors: [], stocks: [stock], selected: stock }
    service = Object.new
    service.define_singleton_method(:call) { |mode:| result }
    MarketDashboard.stub(:new, ->(*) { service }) do
      post refresh_market_dashboard_path, params: { mode: "leaders" }
      assert_response :success
      assert_select '[data-market-selected] svg[role="img"]', count: 4
      assert_select '[data-market-selected] [data-market-chart="1Y"]:not([hidden])', count: 1
      assert_select '[data-market-selected] [data-market-range][aria-pressed="true"]', count: 1
      assert_includes response.body, "not an intraday chart"
      assert_includes response.body, "120 requests"
    end
  end

  test "five distinct colorful chart panels render on the authenticated default Dashboard" do
    history = { "points" => [{ "date" => "2026-11-05", "close" => 10, "open" => 9, "high" => 11, "low" => 8 },
      { "date" => "2026-11-06", "close" => 12, "open" => 11, "high" => 13, "low" => 10 }] }
    stocks = %w[ALPHA BRAVO CHARLIE DELTA ECHO].map { |ticker| { ticker: ticker, name: "Original #{ticker}", history: history, quote: nil } }
    service = Object.new
    service.define_singleton_method(:call) { |mode:| { received_at: Time.current.utc, requests: 8, stocks: stocks, selected: stocks.first, errors: [] } }
    MarketDashboard.stub(:new, ->(*) { service }) do
      get dashboard_path
      assert_response :success
      assert_select "h1", text: "Dashboard"
      assert_select "[data-market-color]", count: 5
      colors = Nokogiri::HTML(response.body).css("[data-market-color]").map { |node| node["data-market-color"] }
      assert_equal 5, colors.uniq.size
      assert_select '[data-market-points][tabindex="0"]', count: 20
      assert_select '[data-market-color] [data-market-chart]:not([hidden])', count: 5
      assert_not_includes response.body, ">Demo dashboard<"
    end
  end

  test "sign in defaults to Dashboard and old demo bookmarks route there" do
    sign_out users(:one)
    user = users(:one)
    user.update!(password: "Original-dashboard-login-123", password_confirmation: "Original-dashboard-login-123")
    post user_session_path, params: { user: { email: user.email, password: "Original-dashboard-login-123" } }
    assert_redirected_to dashboard_path
    get root_path
    assert_redirected_to dashboard_path
    get portfolio_demo_path
    assert_redirected_to dashboard_path
  end
end
