module ResearchOwnership
  extend ActiveSupport::Concern

  included do
    belongs_to :user
    before_save :serialize_research_owner
    before_destroy :serialize_research_owner
  end

  private

  def serialize_research_owner
    # Share cutover's row lock; callers must never hold it across provider calls.
    user.lock!
  end
end
