class SandboxStrategy
  # Fixed declarative rule: one fictional instrument, two observations, integer units.
  RULE = { version: "trend-v1", instrument: "SYNTH-ALPHA", horizon: "two fictional observations",
           buy: "last > prior", sell: "last < prior", otherwise: "hold" }.freeze

  def self.decide!(version:, fixture:)
    raise SandboxLedger::Denied, "Unsupported rule version." unless version == RULE[:version]
    return :buy if fixture.fetch(:price) > fixture.fetch(:prior)
    return :sell if fixture.fetch(:price) < fixture.fetch(:prior)

    :hold
  end
end
