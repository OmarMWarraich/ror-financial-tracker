class DemoPortfolio
  SCENARIOS = {
    "complete" => "Complete sample",
    "missing_price" => "Missing price",
    "missing_cost" => "Missing cost basis",
    "empty" => "Empty portfolio"
  }.freeze
  OBSERVED_AT = "2026-11-05T00:00:00Z".freeze

  def self.build(scenario: "complete")
    raise ArgumentError, "Unknown demo scenario" unless SCENARIOS.key?(scenario)

    holdings = [
      { ticker: "DEMO-A", name: "Atlas Example", quantity: "10", unit_cost: "80", price: "100" },
      { ticker: "DEMO-B", name: "Beacon Example", quantity: "5", unit_cost: "120", price: "100" },
      { ticker: "DEMO-C", name: "Cedar Example", quantity: "20", unit_cost: "20", price: "25" }
    ]
    case scenario
    when "missing_price" then holdings.first[:price] = nil
    when "missing_cost" then holdings.first[:unit_cost] = nil
    when "empty" then holdings.clear
    end
    PortfolioAnalytics.new(holdings: holdings)
  end
end
