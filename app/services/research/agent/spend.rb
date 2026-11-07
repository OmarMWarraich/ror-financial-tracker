module Research
  module Agent
    class Spend
      def self.cost(user_id: nil)
        scopes = [ResearchEmbeddingAttempt, ResearchModelAttempt].map do |model|
          rows = model.where(budget_date: Time.current.utc.to_date).where.not(state: "released")
          user_id ? rows.where(user_id: user_id) : rows
        end
        scopes.sum { |rows| rows.sum("COALESCE(actual_cost_nanos, reserved_cost_nanos)") } + holds(user_id: user_id)
      end

      def self.holds(user_id: nil, runs: nil)
        rows = runs || ResearchAgentRun.where(budget_date: Time.current.utc.to_date, state: %w[queued running])
        rows = rows.where(user_id: user_id) if user_id
        rows.sum { |run| [run.reserved_cost_nanos - used(run), 0].max }
      end

      def self.used(run)
        run.model_attempts.where.not(state: "released").sum("COALESCE(actual_cost_nanos, reserved_cost_nanos)") +
          ResearchEmbeddingAttempt.where(retrieval_id: run.retrievals.select(:id)).where.not(state: "released")
            .sum("COALESCE(actual_cost_nanos, reserved_cost_nanos)")
      end

      def self.conversation(conversation)
        conversation.runs.sum { |run| used(run) } +
          holds(runs: conversation.runs.where(state: %w[queued running]))
      end
    end
  end
end
