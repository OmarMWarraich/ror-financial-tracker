class ResearchMessage < ApplicationRecord
  include ResearchOwnership
  belongs_to :conversation, class_name: "ResearchConversation"
  belongs_to :run, class_name: "ResearchAgentRun"
  encrypts :content
  self.filter_attributes += [:content]
  validate do
    errors.add(:run, "must belong to the conversation and owner") if run &&
      (run.conversation_id != conversation_id || run.user_id != user_id || conversation.user_id != user_id)
  end
  attr_readonly :user_id, :conversation_id, :run_id, :role, :expires_at

  def readable_content!
    raise Research::Error.new("chat_retention_expired") if expires_at <= Time.current || state == "redacted"
    Research::Agent::Lifecycle.authorize_read!(self)
    if role == "assistant" && source_ids.any? && run.retrievals.any?
      Research::EvidenceSet.restore!(run.retrievals.first, display_only: true).recheck!
    end
    content
  end
end
