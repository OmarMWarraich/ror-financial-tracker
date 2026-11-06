ENV["RAILS_ENV"] ||= "test"
require_relative "../../config/environment"
require "minitest/autorun"
require "minitest/mock"
require "rack/test"

class PortfolioDemoTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Rails.application
  end

  def test_public_demo_renders_without_authentication_or_external_api_calls
    Net::HTTP.stub(:start, ->(*) { flunk "Demo must not request external data" }) do
      get "/portfolio_demo"
    end
    assert_equal 200, last_response.status
    document = Nokogiri::HTML(last_response.body)
    assert_equal "Portfolio analytics", document.at_css("h1").text
    assert_equal "$2,000.00", document.at_css('[data-testid="total-value"]').text
    assert_equal "$1,800.00", document.at_css('[data-testid="cost-basis"]').text
    assert_equal "$200.00", document.at_css('[data-testid="gain-loss"]').text
    assert_equal 3, document.css("tbody tr").length
    assert_equal ["50.0", "25.0", "25.0"], document.css("meter").map { |node| node["value"] }
    assert_includes document.text, "fictional"
    assert_includes document.text, "Hotwire Native iOS and Android"
    assert_empty document.css('input[type="password"]')
  end

  def test_missing_price_is_explicit_and_partial_subtotal_is_not_total
    get "/portfolio_demo", scenario: "missing_price"
    assert_equal 200, last_response.status
    document = Nokogiri::HTML(last_response.body)
    assert_equal "Unavailable", document.at_css('[data-testid="total-value"]').text
    assert_equal "Unavailable", document.at_css('[data-testid="gain-loss"]').text
    assert_includes document.text, "Valuation is incomplete"
    assert_includes document.text, "priced subtotal: $1,000.00"
    assert_equal 2, document.css("meter").length
  end

  def test_missing_cost_is_not_a_zero_gain
    get "/portfolio_demo", scenario: "missing_cost"
    assert_equal 200, last_response.status
    document = Nokogiri::HTML(last_response.body)
    assert_equal "$2,000.00", document.at_css('[data-testid="total-value"]').text
    assert_equal "Unavailable", document.at_css('[data-testid="cost-basis"]').text
    assert_equal "Unavailable", document.at_css('[data-testid="gain-loss"]').text
  end

  def test_empty_scenario_explains_undefined_allocation
    get "/portfolio_demo", scenario: "empty"
    assert_equal 200, last_response.status
    document = Nokogiri::HTML(last_response.body)
    assert_empty document.css("tbody tr")
    assert_empty document.css("meter")
    assert_includes document.text, "No sample holdings"
    assert_includes document.text, "Allocation is undefined"
  end

  def test_unknown_or_structured_scenarios_are_bad_requests
    ["unknown", ["complete"], { "name" => "complete" }].each do |scenario|
      get "/portfolio_demo", scenario: scenario
      assert_equal 400, last_response.status
    end
  end

  def test_existing_private_portfolio_still_requires_sign_in
    get "/my_portfolio"
    assert_equal 302, last_response.status
    assert_equal "/users/sign_in", URI(last_response.location).path
  end

  def test_demo_has_no_write_route
    post "/portfolio_demo"
    assert_equal 404, last_response.status
  end

  def test_holdings_include_source_observation_time_cost_and_weight
    get "/portfolio_demo"
    document = Nokogiri::HTML(last_response.body)
    assert_equal "no-store", last_response.headers["cache-control"]
    assert_includes document.at_css('[aria-label="Source and freshness"]').text, "static / not live"
    assert_includes document.text, "not provider market time or request receipt time"
    headings = document.css("thead th").map(&:text)
    ["Quantity", "Unit cost", "Cost basis", "Observed price", "Value", "Weight", "Price provenance"].each do |heading|
      assert_includes headings, heading
    end
    document.css("tbody tr").each do |row|
      assert_equal DemoPortfolio::OBSERVED_AT, row.at_css("time")["datetime"]
      assert_includes row.text, DemoPortfolio::SOURCE
    end
    assert_equal "$800.00", document.at_css("tbody tr").css("td")[2].text
    assert_equal "50.0%", document.at_css("tbody tr").css("td")[5].text
    assert_includes document.text, "Watchlist membership is not holdings"

    get "/portfolio_demo", scenario: "missing_price"
    row = Nokogiri::HTML(last_response.body).at_css("tbody tr")
    assert_nil row.at_css("time")
    assert_includes row.text, "Observation time unavailable"
  end

  def test_formulas_show_exact_operands_and_rounding_is_display_only
    get "/portfolio_demo"
    document = Nokogiri::HTML(last_response.body)
    formula = document.css('[data-testid="worked-formula"]').first.text.gsub(/\s+/, " ")
    assert_includes formula, "Value: 10.0 × 100.0 = 1000.0 USD"
    assert_includes formula, "Cost: 10.0 × 80.0 = 800.0 USD"
    assert_includes formula, "Gain/loss: 1000.0 − 800.0 = 200.0 USD"
    assert_includes formula, "Weight: 1000.0 ÷ 2000.0 × 100 = 50.0%"
    assert_includes document.text, "money-weighted, or time-weighted"
    assert_includes document.text, "equality is not flagged"
    assert_includes document.text, "Rules use unrounded inputs"
    helper = ApplicationController.helpers
    assert_equal "$1.01", helper.demo_money(BigDecimal("1.005"))
    assert_equal "-$1.01", helper.demo_money(BigDecimal("-1.005"))
    assert_equal "40.1%", helper.demo_weight(BigDecimal("40.05"))
    assert_equal "0.00001", helper.demo_decimal(BigDecimal("0.00001"))
    assert_equal "Unavailable", helper.demo_money(nil)
    assert_equal "Unavailable", helper.demo_weight(nil)
  end

  def test_walkthrough_is_sanitized_and_live_features_are_visibly_gated
    get "/portfolio_demo"
    document = Nokogiri::HTML(last_response.body)
    assert_equal 5, document.css('[data-testid="architecture-diagram"] li').length
    assert_equal 5, document.css('[data-testid="request-flow-diagram"] li').length
    shape = JSON.parse(document.at_css(".demo-json code").text)
    assert_equal "synthetic", shape.fetch("mode")
    assert_equal "USD", shape.fetch("currency")
    assert_equal "DEMO-A", shape.fetch("ticker")
    assert_equal "10.0", shape.fetch("quantity")
    assert_equal "1000.0", shape.fetch("value")
    assert_equal "800.0", shape.fetch("cost_basis")
    assert_equal "200.0", shape.fetch("gain_loss")
    assert_equal "50.0", shape.fetch("weight")
    assert_nil shape.fetch("price_received_at")
    assert_equal DemoPortfolio::OBSERVED_AT, shape.fetch("price_observed_at")
    assert_empty shape.keys.grep(/account|key|token|secret|user/)
    ["Sector analysis: gated", "Company evidence: gated", "History and performance: gated",
     "Corporate-action treatment", "aligned dates", "Provider-backed extension",
     "caching/retention rights", "rate-limit", "malformed-response", "no provider cache",
     "not a provider response", "original observation time"].each do |text|
      assert_includes document.text, text
    end
    assert_empty document.css("canvas, svg, iframe"), "No invented time series or embedded provider pages"
  end

  def test_simulated_loading_and_provider_error_never_render_success_fallbacks
    DemoPortfolio::STATES.each_key do |scenario|
      get "/portfolio_demo", scenario: scenario
      assert_equal 200, last_response.status
      document = Nokogiri::HTML(last_response.body)
      assert_includes document.at_css('[data-testid="evidence-state"]').text, DemoPortfolio::STATES.fetch(scenario)
      assert_empty document.css('[data-testid="total-value"], [data-testid="gain-loss"], meter, tbody tr')
      assert_includes document.text, "Choose another scenario explicitly"
    end
  end

  def test_all_scenarios_ignore_private_parameters_and_do_not_write_or_call_providers
    writes = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
      sql = args.last[:sql].to_s
      writes << sql if sql.match?(/\b(?:INSERT|UPDATE|DELETE|REPLACE|TRUNCATE|CREATE|ALTER|DROP)\b/i)
    end
    no_network = ->(*) { flunk "Synthetic scenario must not call a provider" }
    Net::HTTP.stub(:start, no_network) do
      EquiblesClient.stub(:new, no_network) do
        DemoPortfolio::SCENARIOS.each_key do |scenario|
          get "/portfolio_demo", scenario: scenario, api_key: "PRIVATE_SENTINEL", account_id: "PRIVATE_ACCOUNT",
                                 holdings: [{ ticker: "UNTRUSTED-HOLDING", quantity: "999" }]
          assert_equal 200, last_response.status
          refute_includes last_response.body, "PRIVATE_SENTINEL"
          refute_includes last_response.body, "PRIVATE_ACCOUNT"
          refute_includes last_response.body, "UNTRUSTED-HOLDING"
          document = Nokogiri::HTML(last_response.body)
          assert_empty document.css('input[type="password"], input[name*="key"], input[name*="account"]')
          assert_equal ["get"], document.css("form").map { |form| form["method"].downcase }.uniq
        end
      end
    end
    assert_empty writes, "Public synthetic reads must not persist private holdings or other SQL writes"
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  def test_accessible_controls_tables_diagrams_and_chart_text
    get "/portfolio_demo"
    document = Nokogiri::HTML(last_response.body)
    assert_equal "scenario", document.at_css('label[for="scenario"]')["for"]
    assert document.at_css('select#scenario[name="scenario"]')
    submit = document.at_css('button[type="submit"][name="commit"][value="Show scenario"]')
    assert submit
    assert_equal "Show scenario", submit.text.strip
    assert document.at_css('.table-responsive[role="region"][tabindex="0"][aria-label]')
    assert document.at_css("table caption")
    assert_equal 9, document.css('thead th[scope="col"]').length
    assert_equal 3, document.css('tbody th[scope="row"]').length
    document.css("meter").each do |meter|
      assert document.at_css("[id='#{meter["aria-labelledby"]}']")
      assert_includes meter.text, "%"
    end
    document.css("figure").each do |figure|
      assert document.at_css("[id='#{figure["aria-labelledby"]}']")
      assert figure.at_css("ol")
    end
    assert_operator document.css("details > summary").length, :>=, 2
    assert document.at_css(".demo-json[tabindex='0'][aria-label]")
    assert document.at_css(".col-12.col-lg-6"), "Allocation cards retain narrow/wide responsive breakpoints"
  end
end
