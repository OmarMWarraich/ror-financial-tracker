class SandboxFixtures
  INSTRUMENT = "SYNTH-ALPHA".freeze
  PROVENANCE = "Hand-authored fictional USD unit prices; mechanics fixture v1. Not a security, quote, market session, history, forecast, or broker fill.".freeze
  TTL = 15.minutes
  DATA = {
    "rise-v1" => [99, 100].freeze,
    "fall-v1" => [101, 100].freeze,
    "flat-v1" => [100, 100].freeze
  }.freeze

  def self.fetch!(account, now: Time.current)
    values = DATA[account.fixture_key]
    age = account.fixture_loaded_at && now - account.fixture_loaded_at
    unless values && age && age >= 0 && age <= TTL
      raise SandboxLedger::Denied, "Missing, stale, or future-dated synthetic fixture; explicitly reload a fixture."
    end
    { key: account.fixture_key, prior: BigDecimal(values.first.to_s),
      price: BigDecimal(values.last.to_s),
      digest: Digest::SHA256.hexdigest([account.fixture_key, values, PROVENANCE].to_json) }.freeze
  end
end
