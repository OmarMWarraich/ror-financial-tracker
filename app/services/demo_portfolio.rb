class DemoPortfolio
  SCENARIOS = {
    "complete" => "Complete sample",
    "missing_price" => "Missing price",
    "missing_cost" => "Missing cost basis",
    "empty" => "Empty portfolio",
    "loading" => "Loading (simulated)",
    "provider_error" => "Provider error (simulated)"
  }.freeze
  OBSERVED_AT = "2026-11-05T00:00:00Z".freeze
  SOURCE = "Original synthetic fixture".freeze
  STATES = {
    "loading" => "Loading preview: evidence is not available yet. No refresh or background request is running.",
    "provider_error" => "Provider-error preview: evidence is unavailable. No provider was contacted; no synthetic success replaces a failed response."
  }.freeze

  def self.build(scenario: "complete")
    unless SCENARIOS.key?(scenario) && !STATES.key?(scenario)
      raise ArgumentError, "Scenario has no portfolio evidence"
    end

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
    holdings.each do |holding|
      holding[:price_source] = SOURCE if holding[:price]
      holding[:price_observed_at] = OBSERVED_AT if holding[:price]
    end
    PortfolioAnalytics.new(holdings: holdings)
  end
end
