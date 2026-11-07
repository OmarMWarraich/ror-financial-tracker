class ResearchConversation < ApplicationRecord
  include ResearchOwnership
  has_many :runs, class_name: "ResearchAgentRun", foreign_key: :conversation_id, dependent: :restrict_with_error
  has_many :messages, class_name: "ResearchMessage", foreign_key: :conversation_id, dependent: :restrict_with_error
  attr_readonly :user_id, :scope, :limits, :expires_at
end
