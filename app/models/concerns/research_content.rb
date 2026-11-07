require "digest"

module ResearchContent
  extend ActiveSupport::Concern

  included do
    before_validation do
      self.checksum = Digest::SHA256.hexdigest(content.to_s) if content_changed? || checksum.blank?
    end
    validates :content, presence: true
    validates :checksum, format: { with: /\A[a-f0-9]{64}\z/ }
    attr_readonly :content, :checksum
  end
end
