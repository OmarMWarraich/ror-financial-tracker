class ResearchToolAttempt < ApplicationRecord
  include ResearchOwnership
  belongs_to :run, class_name: "ResearchAgentRun"
  validate do
    errors.add(:user, "must own the run") if run && run.user_id != user_id
  end
  attr_readonly :user_id, :run_id, :call_id, :name, :arguments_digest
end
