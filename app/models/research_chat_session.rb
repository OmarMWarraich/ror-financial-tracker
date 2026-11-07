class ResearchChatSession < ApplicationRecord
  belongs_to :user
  self.filter_attributes += [:token_digest, :authentication_digest]
  LIFETIME = 30.minutes

  def self.issue!(user)
    token = SecureRandom.hex(32)
    record = create!(user: user, token_digest: Digest::SHA256.hexdigest(token),
      authentication_digest: Digest::SHA256.hexdigest(user.encrypted_password), expires_at: Time.current + LIFETIME)
    [record, token]
  end

  def valid_access?
    revoked_at.nil? && expires_at > Time.current &&
      authentication_digest == Digest::SHA256.hexdigest(user.reload.encrypted_password)
  end
end
