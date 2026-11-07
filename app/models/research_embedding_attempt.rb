class ResearchEmbeddingAttempt < ApplicationRecord
  include ResearchOwnership
  belongs_to :ingestion, class_name: "ResearchIngestion", optional: true
  belongs_to :retrieval, class_name: "ResearchRetrieval", optional: true
  validates :state, inclusion: { in: %w[reserved dispatched settled uncertain released] }
  validates :reserved_tokens, inclusion: { in: 1..3200 }
  validate do
    errors.add(:base, "must have exactly one owner request") if ingestion_id.nil? == retrieval_id.nil?
    request = ingestion || retrieval
    errors.add(:user, "must own the request") if request && request.user_id != user_id
  end

  # Nanodollars preserve the selected model's $0.02/1M-token price without rounding to cents.
  PRICE_PER_TOKEN = 20
  GLOBAL_LOCK = 7_411_602

  def self.reserve!(request, tokens:, batch_key:, paid:)
    association = case request
    when ResearchIngestion then :ingestion
    when ResearchRetrieval then :retrieval
    else raise Research::Error.new("invalid_embedding_owner_request")
    end
    transaction do
      request.user.lock!
      connection.execute("SELECT pg_advisory_xact_lock(#{GLOBAL_LOCK})")
      if where(user_id: request.user_id, batch_key: batch_key, state: %w[dispatched uncertain]).exists?
        raise Research::Error.new("uncertain_usage_requires_review")
      end
      if ResearchModelAttempt.where(user_id: request.user_id, state: %w[dispatched uncertain]).exists?
        raise Research::Error.new("uncertain_usage_requires_review")
      end
      today = Time.current.utc.to_date
      live = where(budget_date: today).where.not(state: "released")
      owner = live.where(user_id: request.user_id)
      cost = paid ? tokens * PRICE_PER_TOKEN : 0
      owner_tokens = owner.sum("COALESCE(actual_tokens, reserved_tokens)")
      run_cost = where(association => request).where.not(state: "released").sum("COALESCE(actual_cost_nanos, reserved_cost_nanos)")
      if request.is_a?(ResearchRetrieval) && request.agent_run
        run = request.agent_run
        run_cost = run.model_attempts.where.not(state: "released").sum("COALESCE(actual_cost_nanos, reserved_cost_nanos)") +
          where(retrieval_id: run.retrievals.select(:id)).where.not(state: "released").sum("COALESCE(actual_cost_nanos, reserved_cost_nanos)")
      end
      if owner_tokens + tokens > 20_000 || Research::Agent::Spend.cost(user_id: request.user_id) + cost > 500_000_000 ||
         Research::Agent::Spend.cost + cost > 1_000_000_000 ||
         run_cost + cost > 50_000_000
        raise Research::Error.new("embedding_budget_exceeded")
      end
      create!(association => request, user: request.user, generation: request.generation,
              budget_date: today, batch_key: batch_key, reserved_tokens: tokens, reserved_cost_nanos: cost)
    end
  end

  def reconcile!(tokens: nil, error_code: nil)
    user.with_lock do
      self.class.connection.execute("SELECT pg_advisory_xact_lock(#{GLOBAL_LOCK})")
      reload
      update!(state: tokens.nil? ? "uncertain" : "settled", actual_tokens: tokens,
              actual_cost_nanos: tokens.nil? ? nil : (reserved_cost_nanos.zero? ? 0 : tokens * PRICE_PER_TOKEN),
              error_code: error_code)
    end
  end
end
