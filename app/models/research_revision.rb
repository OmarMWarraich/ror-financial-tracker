class ResearchRevision < ApplicationRecord
  include ResearchContent
  include ResearchOwnership

  belongs_to :document, class_name: "ResearchDocument", inverse_of: :revisions
  has_many :passages, class_name: "ResearchPassage", foreign_key: :revision_id,
           inverse_of: :revision, dependent: :restrict_with_error

  validates :source_revision, :received_at, :expires_at, presence: true
  validates :source_revision, uniqueness: { scope: :document_id }
  validates :index_state, inclusion: { in: %w[pending ready failed] }
  validates :expires_at, comparison: { greater_than: :received_at }, if: -> { received_at && expires_at }
  validates :fresh_until, comparison: { less_than_or_equal_to: :expires_at }, allow_nil: true,
            if: -> { expires_at }
  validate do
    errors.add(:document, "must belong to the same owner") if document && document.user_id != user_id
  end
  attr_readonly :user_id, :document_id, :source_revision, :source_metadata
  self.filter_attributes += [:content, :source_metadata]

  scope :available_at, ->(time) {
    where(revoked_at: nil, index_state: "ready", superseded_at: nil)
      .where(id: ResearchDocument.select(:current_revision_id))
      .where("research_revisions.expires_at > ?", time)
      .where("research_revisions.known_at <= ? AND research_revisions.received_at <= ?", time, time)
  }
end
