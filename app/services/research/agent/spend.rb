module Research
  module Agent
    class Spend
      def self.cost(user_id: nil)
        scopes = [ResearchEmbeddingAttempt, ResearchModelAttempt].map do |model|
          rows = model.where(budget_date: Time.current.utc.to_date).where.not(state: "released")
          user_id ? rows.where(user_id: user_id) : rows
        end
        scopes.sum { |rows| rows.sum("COALESCE(actual_cost_nanos, reserved_cost_nanos)") }
      end
    end
  end
end
