module Research
  module Agent
    class Lifecycle
      LEASE = 20.seconds
      WORKFLOW = "research-agent-v1"

      def self.submit!(user:, query:, request_key:, conversation: nil, preferences: {}, evidence: nil, enqueue: true, **scope)
        if conversation && (!conversation.is_a?(ResearchConversation) || !conversation.persisted? || conversation.user_id != user.id)
          raise Research::Error.new("invalid_research_conversation")
        end
        validator = Runtime.new(user: user, query: query, request_key: request_key, evidence: evidence, **scope)
        selectors = validator.selectors
        limits = Limits.resolve(preferences, ceiling: conversation ? conversation.limits : Limits::DEFAULT)
        run = nil
        user.with_lock do
          ApplicationRecord.connection.execute("SELECT pg_advisory_xact_lock(#{ResearchEmbeddingAttempt::GLOBAL_LOCK})")
          existing = user.research_agent_runs.find_by(request_key: request_key)
          if existing
            unless existing.query_digest == Digest::SHA256.hexdigest(query) && existing.selectors == selectors &&
                   existing.limits == limits && (!conversation || existing.conversation_id == conversation.id)
              raise Research::Error.new("agent_submission_conflict")
            end
            return existing
          end
          unless EquiblesConnection.encryption_configured?
            raise Research::Error.new("chat_encryption_required")
          end
          if conversation && (conversation.user_id != user.id || conversation.scope != selectors || conversation.expires_at <= Time.current)
            raise Research::Error.new("invalid_research_conversation")
          end
          provider = selectors["evidence_mode"] == "fixture" ? "fixture" : "openai"
          draft = ResearchAgentRun.new(user: user, selectors: selectors, provider: provider, model: provider == "fixture" ? "original-fixture-v1" : MODEL)
          settings = Policy.new(user).check!(draft)
          fingerprints = Policy.fingerprints(user, draft, settings)
          retention = chat_retention!(draft, settings)
          conversation ||= user.research_conversations.create!(scope: selectors, limits: limits,
            expires_at: Time.current + retention)
          raise Research::Error.new("conversation_turn_limit") if conversation.runs.count >= limits["turns"]
          hold = provider == "fixture" ? 0 : limits["run_cost_nanos"]
          if Spend.cost(user_id: user.id) + hold > limits["owner_daily_nanos"] ||
             Spend.cost + hold > limits["app_daily_nanos"] ||
             Spend.conversation(conversation) + hold > limits["conversation_cost_nanos"]
            raise Research::Error.new("agent_spend_budget_exceeded")
          end
          if provider != "fixture" && (ResearchModelAttempt.where(user: user, state: %w[dispatched uncertain]).exists? ||
              ResearchEmbeddingAttempt.where(user: user, state: %w[dispatched uncertain]).exists?)
            raise Research::Error.new("uncertain_usage_requires_review")
          end
          source = %w[live_mcp mixed].include?(selectors["evidence_mode"]) ? user.equibles_connection : nil
          if source
            SourceQuota.check_capacity!(source, settings: settings, additional: limits["source_requests"])
          elsif %w[live_mcp mixed].include?(selectors["evidence_mode"])
            raise Research::Error.new("equibles_credentials_required")
          end
          run = user.research_agent_runs.create!(conversation: conversation, request_key: request_key,
            query_digest: Digest::SHA256.hexdigest(query), selectors: selectors, limits: limits, pricing: Limits.pricing,
            credential_fingerprints: fingerprints,
            provider: provider, model: draft.model, prompt_version: PROMPT_VERSION, workflow_version: WORKFLOW,
            state: "queued", budget_date: Time.current.utc.to_date, reserved_cost_nanos: hold,
            source_connection: source, reserved_source_requests: source ? limits["source_requests"] : 0,
            deadline_at: [Time.current + limits["seconds"], conversation.expires_at, evidence&.request&.deadline_at].compact.min)
          if evidence
            request = evidence.request.reload
            raise Research::Error.new("evidence_already_used_by_run") if request.agent_run_id
            request.update!(agent_run: run)
          end
          run.messages.create!(user: user, conversation: conversation, role: "user", state: "submitted",
            content: query, expires_at: conversation.expires_at)
        end
        enqueue!(run) if enqueue
        run
      end

      def self.chat_retention!(run, settings)
        return 1.day if run.provider == "fixture"
        seconds = settings["chat_retention_seconds"]
        unless seconds.is_a?(Integer) && seconds.between?(1, 86_400)
          raise Research::Error.new("chat_retention_approval_required")
        end
        [seconds, settings.fetch("retention_seconds"), Time.iso8601(settings.fetch("expires_at")) - Time.current].min
      end

      def self.authorize_read!(message)
        settings = Policy.new(message.user).check!(message.run)
        chat_retention!(message.run, settings)
        if message.run.credential_fingerprints != Policy.fingerprints(message.user, message.run, settings)
          raise Research::Error.new("agent_credentials_or_policy_changed")
        end
      end

      def self.messages!(user:, conversation_id:)
        conversation = user.research_conversations.find(conversation_id)
        conversation.messages.order(:id).map do |message|
          { "id" => message.id, "role" => message.role, "state" => message.state, "content" => message.readable_content! }
        end
      end

      def self.enqueue!(run, wait: nil)
        run.user.with_lock do
          run.reload
          raise Research::Error.new("agent_not_queued") unless run.state == "queued"
          raise Research::Error.new("agent_queue_retry_limit") if run.enqueue_attempts >= 4 || run.deadline_at <= Time.current
          run.update!(enqueue_attempts: run.enqueue_attempts + 1)
        end
        wait ? ResearchAgentJob.perform_in(wait, run.id) : ResearchAgentJob.perform_async(run.id)
        run.update!(enqueued_at: Time.current, error_code: nil)
      rescue RedisClient::Error
        run.update!(error_code: "research_queue_unavailable")
        Rails.logger.warn("Research run #{run.id} queue unavailable; safe enqueue may be retried")
        raise Research::Error.new("research_queue_unavailable"), cause: nil
      end

      def self.claim!(run)
        token = SecureRandom.uuid
        run.user.with_lock do
          ApplicationRecord.connection.execute("SELECT pg_advisory_xact_lock(#{ResearchEmbeddingAttempt::GLOBAL_LOCK})")
          run.reload
          raise Research::Error.new("agent_run_replay_requires_review") unless run.state == "queued"
          raise Research::Error.new("agent_deadline") if run.deadline_at <= Time.current
          limits = Limits.for(run)
          active = ResearchAgentRun.where(state: "running")
          if active.count >= limits["app_parallelism"] || active.where(user_id: run.user_id).count >= limits["owner_parallelism"]
            raise Research::Error.new("agent_concurrency_limit")
          end
          run.update!(state: "running", lease_token: token, lease_until: [Time.current + LEASE, run.deadline_at].min)
        end
        token
      end

      def self.check_lease!(run, token)
        run.reload
        raise Research::Error.new("agent_cancelled") if run.cancel_requested_at
        unless run.state == "running" && run.lease_token == token && run.lease_until && run.lease_until > Time.current
          raise Research::Error.new("agent_lease_lost")
        end
        raise Research::Error.new("agent_budget_window_changed") if run.budget_date != Time.current.utc.to_date
        raise Research::Error.new("model_pricing_changed") unless run.pricing == Limits.pricing
        raise Research::Error.new("chat_retention_expired") if run.conversation.expires_at <= Time.current
        if run.lease_until < Time.current + 10.seconds
          run.update!(lease_until: [Time.current + LEASE, run.deadline_at].min)
        end
        true
      end

      def self.stop!(user:, run_id:)
        user.with_lock do
          run = user.research_agent_runs.find(run_id)
          raise Research::Error.new("agent_already_terminal") unless %w[queued running].include?(run.state)
          run.update!(cancel_requested_at: Time.current)
          terminal!(run, state: "cancelled", code: "agent_cancelled") if run.state == "queued"
          run
        end
      end

      def self.terminal!(run, state:, code:)
        run.user.with_lock do
          run.reload
          return run unless %w[queued running].include?(run.state)
          ApplicationRecord.connection.execute("SELECT pg_advisory_xact_lock(#{ResearchEmbeddingAttempt::GLOBAL_LOCK})")
          run.model_attempts.where(state: "reserved").update_all(state: "released", error_code: code)
          run.model_attempts.where(state: "dispatched").update_all(state: "uncertain", error_code: code)
          run.tool_attempts.where(state: "dispatched").update_all(state: "uncertain", error_code: code)
          run.update!(state: state, error_code: code, finished_at: Time.current, lease_token: nil, lease_until: nil)
          run.messages.find_or_create_by!(role: "assistant") do |message|
            message.user = run.user
            message.conversation = run.conversation
            message.state = "incomplete"
            message.expires_at = run.conversation.expires_at
          end if run.conversation_id
          Rails.logger.warn("Research run #{run.id} terminal state=#{state} code=#{code}; accepted provider work may still be billed")
        end
        run
      end

      def self.recover!
        ResearchAgentRun.where(state: %w[queued running]).find_each do |run|
          run.user.with_lock do
            run.reload
            if run.state == "queued" && run.deadline_at <= Time.current
              terminal!(run, state: "failed", code: "agent_queue_deadline")
            elsif run.state == "running" && (run.deadline_at <= Time.current ||
                (run.conversation_id && (!run.lease_until || run.lease_until <= Time.current)))
              terminal!(run, state: "interrupted", code: "worker_lease_expired_no_replay")
            end
          end
        end
        ResearchMessage.where("expires_at <= ?", Time.current).where.not(state: "redacted")
          .update_all(content: nil, source_ids: [], sources: [], state: "redacted")
      end
    end
  end
end
