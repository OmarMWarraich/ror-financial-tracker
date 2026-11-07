module Research
  module Agent
    class Execution
      def self.call(run, model: nil, tools_factory: nil, events: nil)
        Lifecycle.recover!
        token = Lifecycle.claim!(run)
        message = run.messages.find_by!(role: "user")
        evidence = run.retrievals.first && EvidenceSet.restore!(run.retrievals.first)
        result = Runtime.new(user: run.user, query: message.readable_content!, request_key: run.request_key,
          **run.selectors.except("as_of").symbolize_keys, evidence: evidence, model: model, tools_factory: tools_factory,
          run: run, lease_token: token, events: events, publisher: ->(result) {
            dates = result.sources.flat_map { |source| [source["fresh_until"], source["expires_at"]].compact }.map { |value| Time.iso8601(value) }
            run.messages.create!(user: run.user, conversation: run.conversation, role: "assistant", state: "complete",
              content: result.text, source_ids: result.sources.map { |source| source.fetch("source_id") },
              expires_at: [run.conversation.expires_at, *dates].min)
          }).call
        if result.text.nil?
          run.messages.create!(user: run.user, conversation: run.conversation, role: "assistant", state: "incomplete",
            expires_at: run.conversation.expires_at)
        end
        result
      rescue Research::Error => error
        if token
          state = error.code == "agent_cancelled" ? "cancelled" : "failed"
          Lifecycle.terminal!(run, state: state, code: error.code)
        elsif %w[agent_deadline agent_queue_deadline].include?(error.code)
          Lifecycle.terminal!(run, state: "failed", code: error.code)
        end
        raise
      ensure
        Lifecycle.terminal!(run, state: "interrupted", code: "worker_aborted_no_replay") if token && run.reload.state == "running"
      end
    end
  end
end
