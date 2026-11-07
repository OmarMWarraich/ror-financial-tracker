class ResearchIngestion < ApplicationRecord
  include ResearchOwnership
  belongs_to :space, class_name: "ResearchEmbeddingSpace"
  belongs_to :document, class_name: "ResearchDocument", optional: true
  has_many :embedding_attempts, class_name: "ResearchEmbeddingAttempt", foreign_key: :ingestion_id,
           dependent: :restrict_with_error

  validates :request_key, presence: true, length: { maximum: 100 }, uniqueness: { scope: :user_id }
  validates :provider, inclusion: { in: %w[synthetic equibles] }
  validates :source_kind, inclusion: { in: %w[earnings_transcript earnings_brief] }
  validates :fiscal_year, inclusion: { in: 1900..2200 }
  validates :fiscal_quarter, inclusion: { in: 1..4 }
  validates :listing_identity, format: { with: /\A(?:US|[A-Z]{4}|SYNTH):[A-Z0-9][A-Z0-9.-]{0,19}\z/ }
  validate do
    errors.add(:space, "must belong to the same owner") if space && space.user_id != user_id
    errors.add(:document, "must belong to the same owner") if document && document.user_id != user_id
    errors.add(:fixture_version, "is not allowlisted") if provider == "synthetic" && !%w[v1 v2].include?(fixture_version)
    errors.add(:fixture_version, "is synthetic only") if provider == "equibles" && fixture_version.present?
  end
  attr_readonly :user_id, :space_id, :provider, :source_kind, :listing_identity,
                :fiscal_year, :fiscal_quarter, :request_key, :fixture_version

  def resume!
    user.with_lock do
      reload
      unless state == "failed" || (lease_expires_at && lease_expires_at <= Time.current && state != "ready")
        raise Research::Error.new("not_resumable")
      end
      if embedding_attempts.where(state: %w[dispatched uncertain]).exists?
        raise Research::Error.new("uncertain_usage_requires_review")
      end
      embedding_attempts.where(state: "reserved").update_all(state: "released", updated_at: Time.current)
      update!(state: "pending", generation: generation + 1, lease_token: nil, lease_expires_at: nil, error_code: nil)
    end
    self
  end
end
