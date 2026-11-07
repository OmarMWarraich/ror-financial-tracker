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
      limits = Research::Agent::Limits.for(run)
      if run.conversation_id && run.pricing != Research::Agent::Limits.pricing
        raise Research::Error.new("model_pricing_changed")
      end
      attempts = where(run: run).where.not(state: "released")
      uncertain = where(user_id: run.user_id, state: %w[dispatched uncertain]).exists? ||
        ResearchEmbeddingAttempt.where(user_id: run.user_id, state: %w[dispatched uncertain]).exists?
      raise Research::Error.new("uncertain_usage_requires_review") if uncertain
      used_input = attempts.sum("COALESCE(actual_input_tokens, reserved_input_tokens)")
      used_output = attempts.sum("COALESCE(actual_output_tokens, reserved_output_tokens)")
      unless run.state == "running" && run.deadline_at > Time.current && attempts.count < limits["steps"] &&
             input_tokens.is_a?(Integer) && output_tokens.is_a?(Integer) &&
             input_tokens.between?(1, limits["step_input_tokens"]) && output_tokens.between?(1, limits["output_tokens"]) &&
             used_input + input_tokens <= limits["input_tokens"] && used_output + output_tokens <= limits["output_tokens"]
        raise Research::Error.new("agent_model_budget_exceeded")
      end
      cost = run.provider == "fixture" ? 0 : input_tokens * Research::Agent::INPUT_PRICE + output_tokens * Research::Agent::OUTPUT_PRICE
      embedding_cost = ResearchEmbeddingAttempt.where(retrieval_id: run.retrievals.select(:id)).where.not(state: "released")
        .sum("COALESCE(actual_cost_nanos, reserved_cost_nanos)")
      used_cost = attempts.sum("COALESCE(actual_cost_nanos, reserved_cost_nanos)") + embedding_cost
      increment = run.conversation_id ? [used_cost + cost - run.reserved_cost_nanos, 0].max : cost
      if Research::Agent::Spend.cost(user_id: run.user_id) + increment > limits["owner_daily_nanos"] ||
         Research::Agent::Spend.cost + increment > limits["app_daily_nanos"] ||
         used_cost + cost > limits["run_cost_nanos"] ||
         (run.conversation_id && Research::Agent::Spend.conversation(run.conversation) + increment > limits["conversation_cost_nanos"])
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
      rates = run.conversation_id ? run.pricing : Research::Agent::Limits.pricing
      cost = usage && (reserved_cost_nanos.zero? ? 0 :
        usage.input_tokens * rates.fetch("input_nanos") + usage.output_tokens * rates.fetch("output_nanos"))
      update!(state: usage ? "settled" : "uncertain", actual_input_tokens: usage&.input_tokens,
        actual_output_tokens: usage&.output_tokens, actual_cost_nanos: cost, error_code: error_code)
    end
  end
end
