class EquiblesEntitlement
  REQUIRED = %w[subscription_verified paid_quotes automated_read private_display cache_storage].freeze
  attr_reader :settings

  def initialize(user, configuration: nil)
    configuration ||= Rails.application.config_for(:equibles_entitlements).to_h
    configuration = configuration.is_a?(Hash) ? configuration.deep_stringify_keys : {}
    users = configuration.fetch("verified_users", {})
    settings = users.is_a?(Hash) ? users.fetch(user.id.to_s, {}) : {}
    @settings = settings.is_a?(Hash) ? settings.stringify_keys : {}
  end

  def approved?
    REQUIRED.all? { |right| settings[right] == true } &&
      settings["approval_reference"].is_a?(String) && settings["approval_reference"].present? &&
      valid_limit?("daily_request_budget", 1..100) &&
      valid_limit?("retention_seconds", 1..86_400) &&
      valid_limit?("freshness_seconds", 1..86_400) && approval_current?
  end

  def metadata
    { "scope" => "private_usd_quote_display_only", "approval_reference" => settings["approval_reference"],
      "retention_seconds" => settings["retention_seconds"], "approval_expires_at" => settings["expires_at"],
      "decision_eligible" => false }
  end

  private

  def approval_current?
    return true unless settings.key?("expires_at")
    expiry = settings["expires_at"]
    expiry.is_a?(String) && expiry.match?(/T.*(?:Z|[+-]\d{2}:\d{2})\z/) && Time.iso8601(expiry) > Time.current
  rescue ArgumentError
    false
  end

  def valid_limit?(key, range)
    settings[key].is_a?(Integer) && range.cover?(settings[key])
  end
end
