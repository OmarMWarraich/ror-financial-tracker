module Research
  class RestoreGate
    def self.pending?
      value = ENV.fetch("RESEARCH_RESTORE_PENDING", "0")
      raise Research::Error.new("restore_configuration_invalid") unless %w[0 1].include?(value)
      value == "1"
    end

    def self.check!
      raise Research::Error.new("research_restore_review_required") if pending?
    end

    def self.review!(user: nil)
      raise Research::Error.new("restore_gate_must_be_enabled") unless pending?
      runs = user ? user.research_agent_runs : ResearchAgentRun.all
      runs.where(state: %w[queued running]).find_each do |run|
        Agent::Lifecycle.terminal!(run, state: "interrupted", code: "restore_interrupted_no_replay")
      end
      requests = user ? user.research_ingestions : ResearchIngestion.all
      requests.where(state: %w[pending fetching chunking embedding]).find_each do |request|
        request.user.with_lock do
          request.embedding_attempts.where(state: "reserved").update_all(state: "released", error_code: "restore_interrupted")
          request.embedding_attempts.where(state: "dispatched").update_all(state: "uncertain", error_code: "restore_interrupted")
          request.update!(state: "failed", lease_token: nil, lease_expires_at: nil, error_code: "restore_interrupted")
        end
      end
      retrievals = user ? user.research_retrievals : ResearchRetrieval.all
      retrievals.where(state: %w[pending retrieving]).find_each do |request|
        request.user.with_lock do
          request.embedding_attempts.where(state: "reserved").update_all(state: "released", error_code: "restore_interrupted")
          request.embedding_attempts.where(state: "dispatched").update_all(state: "uncertain", error_code: "restore_interrupted")
          request.update!(state: "failed", selection: [], generation: request.generation + 1, error_code: "restore_interrupted")
        end
      end
      Disposal.sweep!(user: user)
    end
  end
end
