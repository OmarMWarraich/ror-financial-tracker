class ResearchEmbeddingAttempt < ApplicationRecord
  include ResearchOwnership
  belongs_to :ingestion, class_name: "ResearchIngestion"
  validates :state, inclusion: { in: %w[reserved dispatched settled uncertain released] }
  validates :reserved_tokens, inclusion: { in: 1..3200 }

  # Nanodollars preserve the selected model's $0.02/1M-token price without rounding to cents.
  PRICE_PER_TOKEN = 20
  GLOBAL_LOCK = 7_411_602

  def self.reserve!(ingestion, tokens:, batch_key:, paid:)
    transaction do
      connection.execute("SELECT pg_advisory_xact_lock(#{GLOBAL_LOCK})")
      ingestion.user.lock!
      today = Time.current.utc.to_date
      live = where(budget_date: today).where.not(state: "released")
      owner = live.where(user_id: ingestion.user_id)
      cost = paid ? tokens * PRICE_PER_TOKEN : 0
      owner_tokens = owner.sum("COALESCE(actual_tokens, reserved_tokens)")
      owner_cost = owner.sum("COALESCE(actual_cost_nanos, reserved_cost_nanos)")
      run_cost = live.where(ingestion_id: ingestion.id).sum("COALESCE(actual_cost_nanos, reserved_cost_nanos)")
      if owner_tokens + tokens > 20_000 || owner_cost + cost > 500_000_000 ||
         live.sum("COALESCE(actual_cost_nanos, reserved_cost_nanos)") + cost > 1_000_000_000 ||
         run_cost + cost > 50_000_000
        raise Research::Error.new("embedding_budget_exceeded")
      end
      create!(user: ingestion.user, ingestion: ingestion, generation: ingestion.generation,
              budget_date: today, batch_key: batch_key, reserved_tokens: tokens, reserved_cost_nanos: cost)
    end
  end

  def reconcile!(tokens: nil, error_code: nil)
    user.with_lock do
      reload
      update!(state: tokens.nil? ? "uncertain" : "settled", actual_tokens: tokens,
              actual_cost_nanos: tokens.nil? ? nil : (reserved_cost_nanos.zero? ? 0 : tokens * PRICE_PER_TOKEN),
              error_code: error_code)
    end
  end
end
