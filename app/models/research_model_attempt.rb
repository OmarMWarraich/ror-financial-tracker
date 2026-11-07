class ResearchModelAttempt < ApplicationRecord
  include ResearchOwnership
  belongs_to :run, class_name: "ResearchAgentRun"
  validate do
    errors.add(:user, "must own the run") if run && run.user_id != user_id
  end

  def self.reserve!(run, input_tokens:, output_tokens:)
    transaction do
      run.user.lock!
      connection.execute("SELECT pg_advisory_xact_lock(#{ResearchEmbeddingAttempt::GLOBAL_LOCK})")
      run.reload
      attempts = where(run: run).where.not(state: "released")
      uncertain = where(user_id: run.user_id, state: %w[dispatched uncertain]).exists? ||
        ResearchEmbeddingAttempt.where(user_id: run.user_id, state: %w[dispatched uncertain]).exists?
      raise Research::Error.new("uncertain_usage_requires_review") if uncertain
      used_input = attempts.sum("COALESCE(actual_input_tokens, reserved_input_tokens)")
      used_output = attempts.sum("COALESCE(actual_output_tokens, reserved_output_tokens)")
      unless run.state == "running" && run.deadline_at > Time.current && attempts.count < 4 &&
             input_tokens.between?(1, 10_000) && output_tokens.between?(1, 4096) &&
             used_input + input_tokens <= 12_000 && used_output + output_tokens <= 4096
        raise Research::Error.new("agent_model_budget_exceeded")
      end
      cost = run.provider == "fixture" ? 0 : input_tokens * Research::Agent::INPUT_PRICE + output_tokens * Research::Agent::OUTPUT_PRICE
      embedding_cost = ResearchEmbeddingAttempt.where(retrieval_id: run.retrievals.select(:id)).where.not(state: "released")
        .sum("COALESCE(actual_cost_nanos, reserved_cost_nanos)")
      if Research::Agent::Spend.cost(user_id: run.user_id) + cost > 500_000_000 ||
         Research::Agent::Spend.cost + cost > 1_000_000_000 ||
         attempts.sum("COALESCE(actual_cost_nanos, reserved_cost_nanos)") + embedding_cost + cost > 50_000_000
        raise Research::Error.new("agent_spend_budget_exceeded")
      end
      create!(run: run, user: run.user, step: attempts.count + 1, budget_date: Time.current.utc.to_date,
        reserved_input_tokens: input_tokens, reserved_output_tokens: output_tokens, reserved_cost_nanos: cost)
    end
  end

  def reconcile!(usage: nil, error_code: nil)
    user.with_lock do
      self.class.connection.execute("SELECT pg_advisory_xact_lock(#{ResearchEmbeddingAttempt::GLOBAL_LOCK})")
      reload
      cost = usage && (reserved_cost_nanos.zero? ? 0 :
        usage.input_tokens * Research::Agent::INPUT_PRICE + usage.output_tokens * Research::Agent::OUTPUT_PRICE)
      update!(state: usage ? "settled" : "uncertain", actual_input_tokens: usage&.input_tokens,
        actual_output_tokens: usage&.output_tokens, actual_cost_nanos: cost, error_code: error_code)
    end
  end
end
