module PortfolioDemosHelper
  def demo_money(value)
    value.nil? ? "Unavailable" : number_to_currency(value, unit: "$", precision: 2, round_mode: :half_up)
  end

  def demo_weight(value)
    value.nil? ? "Unavailable" : number_to_percentage(value, precision: 1, round_mode: :half_up)
  end

  def demo_decimal(value)
    value.nil? ? "Unavailable" : value.to_s("F")
  end

  def demo_walkthrough_json
    position = DemoPortfolio.build.positions.first
    {
      mode: "synthetic", currency: "USD", price_source: position[:price_source],
      ticker: position[:ticker], name: position[:name],
      quantity: demo_decimal(position[:quantity]), unit_cost: demo_decimal(position[:unit_cost]),
      price: demo_decimal(position[:price]), price_observed_at: position[:price_observed_at],
      price_received_at: position[:price_received_at],
      value: demo_decimal(position[:value]), cost_basis: demo_decimal(position[:cost_basis]),
      gain_loss: demo_decimal(position[:gain_loss]), weight: demo_decimal(position[:weight])
    }.to_json
  end
end
