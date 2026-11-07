class ResearchPassage < ApplicationRecord
  include ResearchContent
  include ResearchOwnership

  belongs_to :revision, class_name: "ResearchRevision", inverse_of: :passages
  has_many :embeddings, class_name: "ResearchEmbedding", foreign_key: :passage_id,
           inverse_of: :passage, dependent: :restrict_with_error

  validates :preprocessing_version, :chunker_version, presence: true
  validates :position, :start_char, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :token_count, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 800 }
  validates :end_char, numericality: { only_integer: true, greater_than: 0 }
  validates :position, uniqueness: { scope: [:revision_id, :preprocessing_version, :chunker_version] }
  validate do
    errors.add(:revision, "must belong to the same owner") if revision && revision.user_id != user_id
    errors.add(:end_char, "must match the content length") unless start_char && end_char && end_char - start_char == content.to_s.length
    unless (start_line.nil? && end_line.nil?) || (start_line.to_i.positive? && end_line && end_line >= start_line)
      errors.add(:start_line, "and end line must form a valid citation range")
    end
  end
  attr_readonly :user_id, :revision_id, :preprocessing_version, :chunker_version,
                :position, :start_char, :end_char, :start_line, :end_line, :speaker
  attr_readonly :source_metadata
  self.filter_attributes += [:content, :source_metadata]

  def self.eligible_for(space, at:)
    joins(revision: :document)
      .where(user_id: space.user_id, preprocessing_version: space.preprocessing_version, chunker_version: space.chunker_version)
      .merge(ResearchRevision.available_at(at))
      .where("research_revisions.expires_at > ?", Time.current)
      .merge(ResearchDocument.retained_at(Time.current))
  end

  def self.indexed_for(space, at:)
    joins(revision: :document)
      .where(user_id: space.user_id, preprocessing_version: space.preprocessing_version, chunker_version: space.chunker_version)
      .where(research_revisions: { revoked_at: nil, index_state: "ready", superseded_at: nil })
      .where("research_revisions.id = research_documents.current_revision_id AND research_revisions.received_at <= ? AND research_revisions.expires_at > ?", at, at)
      .where("research_revisions.known_at IS NULL OR research_revisions.known_at <= ?", at)
      .merge(ResearchDocument.retained_at(Time.current))
  end
end
