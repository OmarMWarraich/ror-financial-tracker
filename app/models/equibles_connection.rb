class EquiblesConnection < ApplicationRecord
  belongs_to :user
  encrypts :api_key
  self.filter_attributes += [:api_key, :snapshot]

  validates :user_id, uniqueness: true
  before_save do
    if (quota_key_digest.blank? || will_save_change_to_api_key?) && self.class.encryption_configured?
      self.quota_key_digest = api_key.nil? ? nil : Digest::SHA256.hexdigest(api_key.strip)
    end
  end
  after_save :record_quota_usage

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

  def record_quota_usage
    records = [
      [quota_key_digest_before_last_save, quota_date_before_last_save, requests_used_before_last_save],
      [quota_key_digest, quota_date, requests_used]
    ].filter_map do |digest, date, used|
      next unless digest && date && used.to_i.positive?
      { user_id: user_id, connection_id: id, key_digest: digest, budget_date: date, requests_used: used }
    end
    records.map { |record| record[:key_digest] }.uniq.sort.each { |key| Research::SourceQuota.account_key_lock!(key) }
    records.group_by { |record| [record[:key_digest], record[:budget_date]] }.each_value do |versions|
      record = versions.max_by { |version| version[:requests_used] }
      ResearchSourceUsage.upsert_all([record], unique_by: "research_source_usage_identity",
        on_duplicate: Arel.sql("requests_used = GREATEST(research_source_usages.requests_used, EXCLUDED.requests_used)"))
    end
  end

  def snapshot_approval_expired?(now)
    expiry = snapshot.dig("entitlement", "approval_expires_at")
    return false if expiry.nil?
    return true unless expiry.is_a?(String) && expiry.match?(/T.*(?:Z|[+-]\d{2}:\d{2})\z/)
    Time.iso8601(expiry) <= now
  rescue ArgumentError
    true
  end
end
