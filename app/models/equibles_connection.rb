class EquiblesConnection < ApplicationRecord
  belongs_to :user
  encrypts :api_key
  self.filter_attributes += [:api_key, :snapshot]

  validates :user_id, uniqueness: true

  def expire_evidence!(entitlement, now: Time.current)
    retention = [entitlement.settings["retention_seconds"], snapshot.dig("entitlement", "retention_seconds")]
                .select { |value| value.is_a?(Integer) && value.positive? }.min
    if !entitlement.approved? || snapshot_approval_expired?(now) ||
       !retention || !last_success_at || last_success_at <= now - retention
      update!(snapshot: {}) if snapshot.present?
    end
  end

  def self.encryption_configured?
    config = ActiveRecord::Encryption.config
    config.primary_key.present? && config.deterministic_key.present? && config.key_derivation_salt.present?
  rescue ActiveRecord::Encryption::Errors::Configuration
    false
  end

  private

  def snapshot_approval_expired?(now)
    expiry = snapshot.dig("entitlement", "approval_expires_at")
    return false if expiry.nil?
    return true unless expiry.is_a?(String) && expiry.match?(/T.*(?:Z|[+-]\d{2}:\d{2})\z/)
    Time.iso8601(expiry) <= now
  rescue ArgumentError
    true
  end
end
