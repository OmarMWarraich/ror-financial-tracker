require "time"

class KrakenMonitoringPolicy
  def self.approved?(user)
    settings = Rails.application.config_for(:kraken_monitoring)
    return false unless settings[:enabled] == true
    unless settings[:approved_users].is_a?(Hash)
      Rails.logger.warn("kraken_monitoring policy requires an owner-specific approval map")
      return false
    end
    review = settings[:approved_users].stringify_keys[user.id.to_s]
    return false unless settings[:enabled] == true && review.is_a?(Hash)

    review = review.stringify_keys
    review["reference"].present? && review["expires_at"].is_a?(String) &&
      Time.iso8601(review["expires_at"]) > Time.current
  rescue ArgumentError
    Rails.logger.warn("kraken_monitoring policy has an invalid review expiry")
    false
  end
end
