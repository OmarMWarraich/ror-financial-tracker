module Research
  module Agent
    class Limits
      DEFAULT = { "steps" => 4, "tools" => 6, "source_requests" => 16, "seconds" => 90,
        "step_input_tokens" => 10_000, "input_tokens" => 12_000, "output_tokens" => 4096,
        "context_tokens" => 6000, "context_bytes" => 65_536, "sources" => 6,
        "history_tokens" => 9000, "owner_parallelism" => 1, "app_parallelism" => 2,
        "run_cost_nanos" => 50_000_000, "conversation_cost_nanos" => 200_000_000,
        "owner_daily_nanos" => 500_000_000, "app_daily_nanos" => 1_000_000_000, "turns" => 4 }.freeze

      def self.resolve(preferences = {}, ceiling: DEFAULT)
        unless preferences.is_a?(Hash) && (preferences.keys - DEFAULT.keys).empty? &&
               preferences.all? { |key, value| value.is_a?(Integer) && value.between?(1, ceiling.fetch(key)) }
          raise Research::Error.new("invalid_agent_limits")
        end
        ceiling.merge(preferences)
      end

      def self.for(run)
        resolve(run.limits)
      end

      def self.pricing
        { "version" => "openai-2026-11-07-v1", "model" => MODEL, "input_nanos" => INPUT_PRICE,
          "output_nanos" => OUTPUT_PRICE, "embedding_nanos" => ResearchEmbeddingAttempt::PRICE_PER_TOKEN }
      end
    end
  end
end
