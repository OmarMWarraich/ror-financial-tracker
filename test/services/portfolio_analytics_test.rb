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

  private

  def holding(**attributes)
    { ticker: "DEMO", name: "Example", quantity: "1", price: "10", unit_cost: "8" }.merge(attributes)
  end
end
