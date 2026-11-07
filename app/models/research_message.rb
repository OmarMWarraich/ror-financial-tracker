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
    if run.retrievals.empty? && run.messages.where(role: "assistant").any? { |message|
        message.sources.any? { |source| source["document_id"] || source["revision_id"] || source["passage_id"] }
      }
      raise Research::Error.new("evidence_dependency_missing")
    end
    run.retrievals.each do |retrieval|
      Research::EvidenceSet.restore!(retrieval, display_only: true).recheck! if retrieval.selection.present?
    end
    content
  end
end
