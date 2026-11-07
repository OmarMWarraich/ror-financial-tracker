class ResearchEmbedding < ApplicationRecord
  include ResearchOwnership
  belongs_to :passage, class_name: "ResearchPassage", inverse_of: :embeddings
  belongs_to :space, class_name: "ResearchEmbeddingSpace", inverse_of: :embeddings
  has_neighbors :embedding, dimensions: 1536

  before_validation do
    if passage
      self.input_checksum ||= passage.checksum
      self.preprocessing_version ||= passage.preprocessing_version
      self.chunker_version ||= passage.chunker_version
    end
  end
  validates :embedding, :input_checksum, :preprocessing_version, :chunker_version, presence: true
  validates :passage_id, uniqueness: { scope: :space_id }
  validate do
    errors.add(:passage, "must belong to the same owner") if passage && passage.user_id != user_id
    errors.add(:space, "must belong to the same owner") if space && space.user_id != user_id
    if passage && input_checksum != passage.checksum
      errors.add(:input_checksum, "must match the passage")
    end
    if passage && (preprocessing_version != passage.preprocessing_version || chunker_version != passage.chunker_version)
      errors.add(:passage, "must match the preprocessing and chunker versions")
    end
    if space && (preprocessing_version != space.preprocessing_version || chunker_version != space.chunker_version)
      errors.add(:space, "must match the passage preprocessing and chunker versions")
    end
    errors.add(:embedding, "must have nonzero norm") if embedding && embedding.all?(&:zero?)
  end
  attr_readonly :user_id, :passage_id, :space_id, :input_checksum,
                :preprocessing_version, :chunker_version, :embedding
end
