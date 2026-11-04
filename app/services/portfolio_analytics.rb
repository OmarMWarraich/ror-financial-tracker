require "bigdecimal"
require "date"
require "time"

class PortfolioAnalytics
  ZERO = BigDecimal("0").freeze
  HUNDRED = BigDecimal("100").freeze

  attr_reader :positions, :concentration_limit

  def initialize(holdings:, concentration_limit: "40")
    @concentration_limit = decimal(concentration_limit, "concentration limit")
    unless @concentration_limit.positive? && @concentration_limit <= HUNDRED
      raise ArgumentError, "Concentration limit must be greater than zero and at most 100"
    end
    @positions = holdings.map { |holding| normalize(holding) }
    tickers = @positions.map { |position| position.fetch(:ticker) }
    raise ArgumentError, "Holdings must have unique tickers" unless tickers.uniq == tickers

    denominator = priced_value
    @positions = @positions.map do |position|
      weight = position[:value] / denominator * HUNDRED if position[:value] && denominator.positive?
      position.merge(weight: weight).freeze
    end.freeze
  end

  def priced_value
    positions.sum(ZERO) { |position| position[:value] || ZERO }
  end

  def total_value
    priced_value if complete_prices?
  end

  def total_cost_basis
    positions.sum(ZERO) { |position| position[:cost_basis] } if complete_cost_basis?
  end

  def unrealized_gain_loss
    total_value - total_cost_basis if complete_prices? && complete_cost_basis?
  end

  def complete_prices?
    positions.all? { |position| !position[:price].nil? }
  end

  def complete_cost_basis?
    positions.all? { |position| !position[:unit_cost].nil? }
  end

  def concentrated_positions
    positions.select { |position| position[:weight] && position[:weight] > concentration_limit }
  end

  private

  def normalize(holding)
    ticker = holding.fetch(:ticker)
    name = holding.fetch(:name)
    unless ticker.is_a?(String) && ticker.match?(/\A[A-Z0-9][A-Z0-9.-]{0,31}\z/) &&
           name.is_a?(String) && !name.strip.empty?
      raise ArgumentError, "Holdings require a valid ticker and name"
    end
    quantity = decimal(holding.fetch(:quantity), "quantity")
    price = decimal(holding[:price], "price", optional: true)
    unit_cost = decimal(holding[:unit_cost], "unit cost", optional: true)
    raise ArgumentError, "Price must be positive when supplied" if price && !price.positive?

    value = quantity * price if price
    cost_basis = quantity * unit_cost if unit_cost
    { ticker: ticker.dup.freeze, name: name.strip.freeze, quantity: quantity,
      price: price, unit_cost: unit_cost, value: value, cost_basis: cost_basis,
      price_source: price ? source(holding[:price_source]) : nil,
      price_observed_at: price ? timestamp(holding[:price_observed_at]) : nil,
      price_received_at: price ? timestamp(holding[:price_received_at]) : nil,
      gain_loss: value && cost_basis ? value - cost_basis : nil }
  end

  def source(value)
    return nil if value.nil?
    raise ArgumentError, "Price source must be a non-empty string" unless value.is_a?(String) && !value.strip.empty?

    value.strip.freeze
  end

  def timestamp(value)
    return nil if value.nil?
    unless value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:Z|[+-]\d{2}:\d{2})\z/)
      raise ArgumentError, "Price timestamp must be ISO 8601 with a time zone"
    end

    DateTime.iso8601(value).to_time.utc.iso8601.freeze
  end

  def decimal(value, field, optional: false)
    return nil if optional && value.nil?

    unless value.is_a?(String) || value.is_a?(Numeric)
      raise ArgumentError, "#{field.capitalize} must be a non-negative finite decimal"
    end
    number = BigDecimal(value.to_s)
    unless number.finite? && number >= ZERO
      raise ArgumentError, "#{field.capitalize} must be a non-negative finite decimal"
    end
    number
  end
end
