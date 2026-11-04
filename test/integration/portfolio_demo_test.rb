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
end
