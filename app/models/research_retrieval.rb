class ResearchRetrieval < ApplicationRecord
  include ResearchOwnership
  belongs_to :space, class_name: "ResearchEmbeddingSpace"
  belongs_to :agent_run, class_name: "ResearchAgentRun", optional: true
  has_many :embedding_attempts, class_name: "ResearchEmbeddingAttempt", foreign_key: :retrieval_id,
           dependent: :restrict_with_error
  validates :request_key, :query_digest, :deadline_at, presence: true
  validates :request_key, uniqueness: { scope: :user_id }
  validates :query_digest, format: { with: /\A[0-9a-f]{64}\z/ }
  validates :state, inclusion: { in: %w[pending retrieving ready no_evidence stale_only failed] }
  validate do
    errors.add(:space, "must belong to the same owner") if space && space.user_id != user_id
    errors.add(:agent_run, "must belong to the same owner") if agent_run && agent_run.user_id != user_id
    errors.add(:selectors, "must be an object") unless selectors.is_a?(Hash)
  end
  attr_readonly :user_id, :space_id, :request_key, :query_digest, :selectors, :deadline_at
end
