class ResearchDisposalJob < ApplicationJob
  queue_as :maintenance

  def perform(user_id = nil)
    user = User.find(user_id) if user_id
    Research::Disposal.sweep!(user: user)
  end
end
