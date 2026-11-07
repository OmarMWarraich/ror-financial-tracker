class ResearchAgentRun < ApplicationRecord
  include ResearchOwnership
  has_many :model_attempts, class_name: "ResearchModelAttempt", foreign_key: :run_id, dependent: :restrict_with_error
  has_many :retrievals, class_name: "ResearchRetrieval", foreign_key: :agent_run_id, dependent: :restrict_with_error
  validates :request_key, :query_digest, :model, :provider, :prompt_version, :deadline_at, presence: true
  validates :request_key, uniqueness: { scope: :user_id }
  validates :query_digest, format: { with: /\A[0-9a-f]{64}\z/ }
  attr_readonly :user_id, :request_key, :query_digest, :selectors, :provider, :model, :prompt_version, :deadline_at
end
