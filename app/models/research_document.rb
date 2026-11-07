class ResearchDocument < ApplicationRecord
  include ResearchOwnership
  belongs_to :current_revision, class_name: "ResearchRevision", optional: true
  has_many :revisions, class_name: "ResearchRevision", foreign_key: :document_id,
           inverse_of: :document, dependent: :restrict_with_error

  validates :provider, :source_id, :instrument_identity, :listing_identity, :entitlement_reference,
            :rights_expires_at, presence: true
  validates :source_kind, inclusion: { in: %w[earnings_brief earnings_transcript filing] }
  validates :fiscal_year, numericality: { only_integer: true, greater_than: 0 }
  validates :fiscal_period, inclusion: { in: %w[Q1 Q2 Q3 Q4 FY] }
  validates :citation_url, format: { with: /\Ahttps:\/\/[^\s]+\z/ }
  validates :source_id, uniqueness: { scope: [:user_id, :provider, :source_kind] }
  attr_readonly :user_id, :provider, :source_kind, :source_id, :instrument_identity,
                :listing_identity, :fiscal_year, :fiscal_period

  scope :retained_at, ->(time) { where(revoked_at: nil).where("research_documents.rights_expires_at > ?", time) }

  def purge_superseded!(keep_revision: nil)
    user.with_lock do
      reload
      keep = keep_revision || current_revision
      unless keep && keep.document_id == id && keep.user_id == user_id
        raise Research::Error.new("no_valid_retained_revision")
      end
      old = revisions.where.not(id: keep.id)
      passages = ResearchPassage.where(revision_id: old.select(:id))
      ResearchEmbedding.where(passage_id: passages.select(:id)).delete_all
      passages.delete_all
      old.delete_all
    end
  end
end
