module PortfolioDemosHelper
  def demo_money(value)
    value.nil? ? "Unavailable" : number_to_currency(value, unit: "$", precision: 2)
  end

  def demo_weight(value)
    value.nil? ? "Unavailable" : number_to_percentage(value, precision: 1)
  end
end
