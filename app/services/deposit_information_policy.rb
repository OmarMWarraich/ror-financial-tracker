require "digest"
require "time"

class DepositInformationPolicy
  # This verifies a local review only, never provider eligibility or capability.
  def self.approved?(user, account_identifier:, asset:, network:,
                     settings: Rails.application.config_for(:kraken_deposit_information), now: Time.current)
    return false unless user&.id && settings.is_a?(Hash) && settings[:enabled] == true
    owners = settings[:approved_users]
    return false unless owners.is_a?(Hash)
    review = owners.transform_keys(&:to_s)[user.id.to_s]
    return false unless review.is_a?(Hash)
    review = review.transform_keys(&:to_s)
    return false unless review["revoked"] == false && review["product"] == "exchange_crypto"
    return false unless review["reference"].is_a?(String) && review["reference"].match?(/\A\S.{0,199}\z/)
    return false unless review["expires_at"].is_a?(String) && Time.iso8601(review["expires_at"]) > now
    return false unless account_identifier.is_a?(String) && account_identifier.match?(/\A[A-Za-z0-9 ]{4,100}\z/)
    return false unless review["account_fingerprint"] == Digest::SHA256.hexdigest(account_identifier)
    return false unless asset.is_a?(String) && network.is_a?(String)
    assets = review["assets"]
    return false unless assets.is_a?(Hash)
    networks = assets.transform_keys(&:to_s)[asset]
    networks.is_a?(Array) && networks.include?(network)
  rescue ArgumentError, TypeError
    false
  end
end
