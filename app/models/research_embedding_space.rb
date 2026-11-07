class ResearchEmbeddingSpace < ApplicationRecord
  include ResearchOwnership
  has_many :ingestions, class_name: "ResearchIngestion", foreign_key: :space_id, dependent: :restrict_with_error
  has_many :retrievals, class_name: "ResearchRetrieval", foreign_key: :space_id, dependent: :restrict_with_error
  has_many :embeddings, class_name: "ResearchEmbedding", foreign_key: :space_id,
           inverse_of: :space, dependent: :restrict_with_error

  validates :provider, :model, :model_version, :preprocessing_version, :chunker_version, presence: true
  validates :dimensions, inclusion: { in: [1536] }
  validates :distance, inclusion: { in: ["cosine"] }
  validates :state, inclusion: { in: %w[building active retired] }
  attr_readonly :user_id, :provider, :model, :model_version, :dimensions, :distance,
                :preprocessing_version, :chunker_version

  def activate!(at: Time.current)
    user.with_lock do
      reload
      raise ArgumentError, "Only a building space can be activated" unless state == "building"
      passages = ResearchPassage.indexed_for(self, at: at)
      if !passages.exists? || passages.where.not(id: embeddings.select(:passage_id)).exists?
        raise ArgumentError, "Complete the eligible passage embeddings before cutover"
      end
      user.research_embedding_spaces.where(state: "active").update_all(state: "retired", updated_at: Time.current)
      update!(state: "active")
    end
  end

  def nearest(query_vector, limit: 5, at: Time.current)
    unless query_vector.is_a?(Array) && query_vector.length == 1536 &&
           query_vector.all? { |value| value.is_a?(Numeric) && value.real? && value.to_f.finite? } &&
           query_vector.any? { |value| !value.zero? }
      raise ArgumentError, "Query must contain 1536 finite values and have nonzero norm"
    end
    raise ArgumentError, "Limit must be between 1 and 100" unless limit.is_a?(Integer) && (1..100).cover?(limit)
    user.with_lock do
      reload
      raise ArgumentError, "Only the active embedding space can be queried" unless state == "active"
      embeddings.where(passage_id: ResearchPassage.eligible_for(self, at: at).select(:id))
        .nearest_neighbors(:embedding, query_vector, distance: "cosine").limit(limit).to_a
    end
  end
end
