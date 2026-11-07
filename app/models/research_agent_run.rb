class ResearchAgentRun < ApplicationRecord
  include ResearchOwnership
  belongs_to :conversation, class_name: "ResearchConversation", optional: true
  belongs_to :source_connection, class_name: "EquiblesConnection", optional: true
  has_many :messages, class_name: "ResearchMessage", foreign_key: :run_id, dependent: :restrict_with_error
  has_many :tool_attempts, class_name: "ResearchToolAttempt", foreign_key: :run_id, dependent: :restrict_with_error
  validate do
    errors.add(:conversation, "must have the same owner") if conversation && conversation.user_id != user_id
    errors.add(:source_connection, "must have the same owner") if source_connection && source_connection.user_id != user_id
  end
  has_many :model_attempts, class_name: "ResearchModelAttempt", foreign_key: :run_id, dependent: :restrict_with_error
  has_many :retrievals, class_name: "ResearchRetrieval", foreign_key: :agent_run_id, dependent: :restrict_with_error
  validates :request_key, :query_digest, :model, :provider, :prompt_version, :deadline_at, presence: true
  validates :request_key, uniqueness: { scope: :user_id }
  validates :query_digest, format: { with: /\A[0-9a-f]{64}\z/ }
  attr_readonly :user_id, :request_key, :query_digest, :selectors, :provider, :model, :prompt_version, :deadline_at
end
