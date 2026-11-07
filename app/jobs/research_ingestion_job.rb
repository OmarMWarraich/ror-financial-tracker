class ResearchIngestionJob < ApplicationJob
  def perform(ingestion_id)
    request = ResearchIngestion.find_by(id: ingestion_id)
    unless request
      Rails.logger.warn("Research ingestion #{ingestion_id} failed code=request_missing")
      return
    end
    Research::Ingestor.new(request).call
  rescue Research::Error => error
    Rails.logger.warn("Research ingestion #{ingestion_id} rejected code=#{error.code}")
  end
end
