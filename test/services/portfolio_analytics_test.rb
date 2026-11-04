require "minitest/autorun"
require_relative "../../app/services/portfolio_analytics"
require_relative "../../app/services/demo_portfolio"

class PortfolioAnalyticsTest < Minitest::Test
  def test_sample_totals_are_exact_decimals
    portfolio = DemoPortfolio.build
    assert_equal BigDecimal("2000"), portfolio.total_value
    assert_equal BigDecimal("1800"), portfolio.total_cost_basis
    assert_equal BigDecimal("200"), portfolio.unrealized_gain_loss
    assert_equal [BigDecimal("50"), BigDecimal("25"), BigDecimal("25")],
                 portfolio.positions.map { |position| position[:weight] }
    assert_equal [BigDecimal("200"), BigDecimal("-100"), BigDecimal("100")],
                 portfolio.positions.map { |position| position[:gain_loss] }
  end

  def test_decimal_quantities_do_not_use_binary_float_arithmetic
    portfolio = PortfolioAnalytics.new(holdings: [holding(quantity: "0.1", price: "0.2", unit_cost: "0.1")])
    assert_equal BigDecimal("0.02"), portfolio.total_value
    assert_equal BigDecimal("0.01"), portfolio.total_cost_basis
    assert_equal BigDecimal("0.01"), portfolio.unrealized_gain_loss
  end

  def test_missing_price_does_not_fabricate_complete_totals
    portfolio = DemoPortfolio.build(scenario: "missing_price")
    refute portfolio.complete_prices?
    assert_nil portfolio.total_value
    assert_nil portfolio.unrealized_gain_loss
    assert_equal BigDecimal("1000"), portfolio.priced_value
    assert_equal BigDecimal("1800"), portfolio.total_cost_basis
    assert_nil portfolio.positions.first[:weight]
    assert_equal [BigDecimal("50"), BigDecimal("50")],
                 portfolio.positions.drop(1).map { |position| position[:weight] }
  end

  def test_missing_cost_preserves_valuation_but_not_gain_loss
    portfolio = DemoPortfolio.build(scenario: "missing_cost")
    refute portfolio.complete_cost_basis?
    assert_equal BigDecimal("2000"), portfolio.total_value
    assert_nil portfolio.total_cost_basis
    assert_nil portfolio.unrealized_gain_loss
    assert_nil portfolio.positions.first[:gain_loss]
  end

  def test_empty_portfolio_has_no_allocation_or_concentration
    portfolio = DemoPortfolio.build(scenario: "empty")
    assert_equal BigDecimal("0"), portfolio.total_value
    assert_empty portfolio.positions
    assert_empty portfolio.concentrated_positions
  end

  def test_zero_quantity_has_no_allocation_denominator
    portfolio = PortfolioAnalytics.new(holdings: [holding(quantity: "0")])
    assert_equal BigDecimal("0"), portfolio.total_value
    assert_nil portfolio.positions.first[:weight]
    assert_empty portfolio.concentrated_positions
  end

  def test_concentration_is_strictly_greater_than_threshold
    at_limit = PortfolioAnalytics.new(holdings: [
      holding(quantity: "40", price: "1"),
      holding(ticker: "OTHER", quantity: "60", price: "1")
    ])
    assert_equal ["OTHER"], at_limit.concentrated_positions.map { |position| position[:ticker] }

    over_limit = PortfolioAnalytics.new(holdings: [
      holding(quantity: "40.01", price: "1"),
      holding(ticker: "OTHER", quantity: "59.99", price: "1")
    ])
    assert_equal ["DEMO", "OTHER"], over_limit.concentrated_positions.map { |position| position[:ticker] }
  end

  def test_invalid_decimal_inputs_raise_instead_of_becoming_zero
    [:quantity, :price, :unit_cost].each do |field|
      ["-1", "NaN", "Infinity", "", "invalid", []].each do |value|
        assert_raises(ArgumentError) { PortfolioAnalytics.new(holdings: [holding(**{ field => value })]) }
      end
    end
    assert_raises(ArgumentError) { PortfolioAnalytics.new(holdings: [holding(quantity: nil)]) }
    assert_raises(ArgumentError) { PortfolioAnalytics.new(holdings: [holding(price: "0")]) }
  end

  def test_missing_all_prices_has_no_weights
    portfolio = PortfolioAnalytics.new(holdings: [holding(price: nil)])
    assert_nil portfolio.total_value
    assert_nil portfolio.positions.first[:weight]
    assert_empty portfolio.concentrated_positions
  end

  def test_invalid_identity_duplicates_and_thresholds_are_rejected
    assert_raises(ArgumentError) { PortfolioAnalytics.new(holdings: [holding(ticker: "../DEMO")]) }
    assert_raises(ArgumentError) { PortfolioAnalytics.new(holdings: [holding(name: "")]) }
    assert_raises(ArgumentError) { PortfolioAnalytics.new(holdings: [holding, holding]) }
    ["0", "-1", "101", "NaN", nil].each do |limit|
      assert_raises(ArgumentError) { PortfolioAnalytics.new(holdings: [], concentration_limit: limit) }
    end
  end

  def test_scenarios_do_not_mutate_subsequent_requests
    DemoPortfolio.build(scenario: "missing_price")
    assert DemoPortfolio.build.complete_prices?
    assert_raises(ArgumentError) { DemoPortfolio.build(scenario: "unknown") }
  end

  def test_sample_provenance_is_static_and_does_not_claim_provider_receipt
    DemoPortfolio.build.positions.each do |position|
      assert_equal DemoPortfolio::SOURCE, position[:price_source]
      assert_equal DemoPortfolio::OBSERVED_AT, position[:price_observed_at]
      assert_nil position[:price_received_at]
    end
    missing = DemoPortfolio.build(scenario: "missing_price").positions.first
    assert_nil missing[:price_source]
    assert_nil missing[:price_observed_at]
    assert_nil missing[:price_received_at]
  end

  def test_observation_and_receipt_are_distinct_optional_normalized_timestamps
    portfolio = PortfolioAnalytics.new(holdings: [
      holding(price_source: " Example source ",
              price_observed_at: "2026-11-05T05:00:00+05:00",
              price_received_at: "2026-11-05T00:02:00Z")
    ])
    position = portfolio.positions.first
    assert_equal "Example source", position[:price_source]
    assert_equal "2026-11-05T00:00:00Z", position[:price_observed_at]
    assert_equal "2026-11-05T00:02:00Z", position[:price_received_at]

    receipt_only = PortfolioAnalytics.new(holdings: [
      holding(price_received_at: "2026-11-05T00:02:00Z")
    ]).positions.first
    assert_nil receipt_only[:price_observed_at], "Receipt time must not become market observation time"
    assert_nil receipt_only[:price_source], "Unknown source must not become a provider claim"

    missing_price = PortfolioAnalytics.new(holdings: [
      holding(price: nil, price_source: "Example source", price_observed_at: DemoPortfolio::OBSERVED_AT)
    ]).positions.first
    assert_nil missing_price[:price_source]
    assert_nil missing_price[:price_observed_at]
  end

  def test_malformed_provenance_is_rejected
    [42, "", "2026-11-05", "2026-11-05T00:00:00", "not-a-time", "2026-99-05T00:00:00Z",
     "2026-02-31T00:00:00Z"].each do |value|
      [:price_observed_at, :price_received_at].each do |field|
        assert_raises(ArgumentError) { PortfolioAnalytics.new(holdings: [holding(**{ field => value })]) }
      end
    end
    ["", " ", 42].each do |value|
      assert_raises(ArgumentError) { PortfolioAnalytics.new(holdings: [holding(price_source: value)]) }
    end
  end

  def test_simulated_loading_and_errors_cannot_build_success_portfolios
    DemoPortfolio::STATES.each_key do |scenario|
      assert DemoPortfolio::SCENARIOS.key?(scenario)
      assert_raises(ArgumentError) { DemoPortfolio.build(scenario: scenario) }
    end
  end

  def test_rounding_does_not_change_concentration_decisions_or_exact_inputs
    portfolio = PortfolioAnalytics.new(holdings: [
      holding(quantity: "40.00001", price: "1"),
      holding(ticker: "OTHER", quantity: "59.99999", price: "1")
    ])
    assert_equal BigDecimal("40.00001"), portfolio.positions.first[:weight]
    assert_equal ["DEMO", "OTHER"], portfolio.concentrated_positions.map { |position| position[:ticker] }

    fractional = PortfolioAnalytics.new(holdings: [
      holding(quantity: "0.00001", price: "123.456", unit_cost: "100.001")
    ])
    assert_equal BigDecimal("0.00123456"), fractional.total_value
    assert_equal BigDecimal("0.00100001"), fractional.total_cost_basis
    assert_equal BigDecimal("0.00023455"), fractional.unrealized_gain_loss
  end

  private

  def holding(**attributes)
    { ticker: "DEMO", name: "Example", quantity: "1", price: "10", unit_cost: "8" }.merge(attributes)
  end
end
