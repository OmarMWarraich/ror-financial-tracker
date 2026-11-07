module Research
  module Agent
    class Runtime
      attr_reader :run

      def initialize(user:, query:, request_key:, listing_identity:, fiscal_year:, fiscal_quarter:,
                     evidence_mode: "fixture", query_mode: "current", evidence: nil, model: nil, tools: nil,
                     policy: nil, cancellation: Cancellation.new, events: nil, publisher: nil, tools_factory: nil)
        @user, @query, @request_key = user, query, request_key
        @evidence, @model, @tools, @cancellation, @sink, @publisher = evidence, model, tools, cancellation, events, publisher
        @policy = policy || Policy.new(user)
        @tools_factory = tools_factory
        @tokenizer = Chunker.new
        @selectors = { "listing_identity" => listing_identity, "fiscal_year" => fiscal_year,
          "fiscal_quarter" => fiscal_quarter, "evidence_mode" => evidence_mode, "query_mode" => query_mode }
        @observations = []
        @forbidden = [ENV["OPENAI_API_KEY"].to_s.strip]
        if user.equibles_connection && EquiblesConnection.encryption_configured?
          @forbidden << user.equibles_connection.api_key.to_s.strip
        end
        Agent.safe_text!(query, forbidden: @forbidden, bytes: 4096)
        unless query.present? && query.length <= 2000 && @tokenizer.tokens(query) <= 500 &&
               request_key.is_a?(String) && request_key.present? && request_key.length <= 128 &&
               %w[fixture retained live_mcp mixed].include?(evidence_mode) && %w[current latest_earnings as_of].include?(query_mode) &&
               listing_identity.is_a?(String) && listing_identity.match?(/\A(?:SYNTH:ALPHA|US:[A-Z][A-Z0-9.-]{0,19})\z/) &&
               fiscal_year.is_a?(Integer) && fiscal_year.between?(1900, 2200) &&
               fiscal_quarter.is_a?(Integer) && fiscal_quarter.between?(1, 4) &&
               (evidence_mode != "fixture" || [listing_identity, fiscal_year, fiscal_quarter] == ["SYNTH:ALPHA", 2026, 3]) &&
               (query_mode != "as_of" || evidence_mode == "retained") &&
               (query_mode != "latest_earnings" || evidence) &&
               (evidence.nil? || (evidence.is_a?(EvidenceSet) && evidence.request.user_id == user.id)) &&
               (!%w[retained mixed].include?(evidence_mode) || evidence)
          raise Research::Error.new("invalid_agent_parameters")
        end
        @selectors["as_of"] = evidence.request.selectors["as_of"] if query_mode == "as_of"
      rescue ActiveRecord::Encryption::Errors::Decryption, ActiveRecord::Encryption::Errors::Configuration
        raise Research::Error.new("equibles_credentials_unavailable"), cause: nil
      end

      def call
        raise Research::Error.new("database_transaction_open") if ApplicationRecord.connection.transaction_open?
        claim!
        @events = Events.new(@run, sink: @sink)
        @events.emit("run.started", "provider" => @run.provider, "model" => @run.model, "evidence_mode" => @selectors["evidence_mode"])
        check!
        sources = local_sources
        if @selectors["evidence_mode"] == "retained" && sources.empty?
          status = @evidence.status == "stale_only" ? "stale_only" : "no_evidence"
          code = status == "stale_only" ? "stale_only" : "no_eligible_evidence"
          @user.with_lock { @run.update!(state: "no_evidence", error_code: code) }
          @events.emit("run.no_evidence", "code" => code)
          return Result.new(run_id: @run.id, status: status, text: nil, sources: [], usage: [])
        end
        fixture = @run.provider == "fixture"
        @model ||= fixture ? FixtureModel.new : OpenaiModel.new
        raise Research::Error.new("fixture_model_required") if fixture && @model.is_a?(OpenaiModel)
        registry = ToolRegistry.new(ticker: @selectors["listing_identity"].split(":").last,
          year: @selectors["fiscal_year"], quarter: @selectors["fiscal_quarter"])
        live = %w[live_mcp mixed fixture].include?(@selectors["evidence_mode"])
        @tools ||= fixture ? FixtureTools.new(registry) :
          (live ? EquiblesMcp.new(user: @user, registry: registry, before_request: method(:before_protocol!)) : nil)
        @tools = @tools_factory.call(registry, method(:before_protocol!)) if @tools_factory && live
        definitions = live ? @tools.discover! : []
        settings = @policy.check!(@run)
        allowed = fixture ? ToolRegistry::FIELDS.keys : settings.fetch("mcp_tools", []).select { |name|
          name == "GetEarningsCallEvent" || settings["source_kinds"].include?(name == "GetEarningsBrief" ? "earnings_brief" : "earnings_transcript")
        }
        definitions = definitions.select { |tool| allowed.include?(tool[:name]) }
        normalizer = ToolEvidence.new(listing: @selectors["listing_identity"], year: @selectors["fiscal_year"],
          quarter: @selectors["fiscal_quarter"], synthetic: fixture, latest_event: latest_event)
        cache = {}
        history = [{ "role" => "user", "content" => JSON.generate("question" => @query,
          "query_mode" => @selectors["query_mode"], "scope" => @selectors, "evidence" => sources) }]
        4.times do
          check!
          raise Research::Error.new("agent_context_budget_exceeded") if @tokenizer.tokens(JSON.generate([history, definitions])) > 9000
          input_tokens = @tokenizer.tokens(JSON.generate([history, definitions])) + 1000
          used_output = @run.model_attempts.where.not(state: "released").sum("COALESCE(actual_output_tokens, reserved_output_tokens)")
          attempt = ResearchModelAttempt.reserve!(@run, input_tokens: input_tokens, output_tokens: 4096 - used_output)
          response = model_step(attempt, history, definitions)
          if response.tool_calls.empty?
            raise Research::Error.new("no_evidence_for_dispatch") if sources.empty?
            Agent.safe_text!(response.text, forbidden: @forbidden)
            raise Research::Error.new("agent_answer_missing_citation") unless sources.any? { |source| response.text.include?(source.fetch("source_id")) }
            close_tools!
            result = Result.new(run_id: @run.id, status: "completed", text: response.text, sources: sources,
              usage: @run.model_attempts.order(:step).map { |row| { "input_tokens" => row.actual_input_tokens, "output_tokens" => row.actual_output_tokens } })
            publish!(result)
            deltas = response.deltas.present? && response.deltas.join == response.text ? response.deltas : [response.text]
            deltas.each { |text| @events.emit("text.delta", "text" => text, "validated" => true) }
            @events.emit("run.completed", "origins" => sources.map { |source| source["origin"] || source["provider"] }.uniq,
              "synthetic" => sources.all? { |source| source["synthetic"] })
            return result
          end
          raise Research::Error.new("agent_step_limit") if attempt.step == 4
          history.concat(response.output)
          response.tool_calls.each do |call|
            raise Research::Error.new("agent_tool_not_authorized") unless allowed.include?(call.name) && live
            registry.validate!(call.name, call.arguments)
            signature = Digest::SHA256.hexdigest(JSON.generate([call.name, call.arguments.sort.to_h]))
            source = cache[signature]
            unless source
              check!
              @user.with_lock do
                @run.reload
                raise Research::Error.new("agent_tool_budget_exceeded") if @run.tool_calls >= 6
                @run.update!(tool_calls: @run.tool_calls + 1)
              end
              @events.emit("tool.started", "name" => call.name)
              raw = @tools.call(call.name, call.arguments, forbidden: @forbidden)
              check!
              source = normalizer.call(call.name, call.arguments, raw, forbidden: @forbidden)
              settings = @policy.check!(@run)
              source["fresh_until"] = (Time.current + (fixture ? 1.day : settings.fetch("freshness_seconds"))).utc.iso8601(6)
              source["expires_at"] = (fixture ? Time.current + 30.days :
                [Time.current + settings.fetch("retention_seconds"), Time.iso8601(settings.fetch("expires_at"))].min).utc.iso8601(6)
              unless @tokenizer.tokens(JSON.generate(source)) <= 6000 && sources.size < 6 &&
                     @tokenizer.tokens(JSON.generate(sources + [source])) <= 6000 &&
                     JSON.generate(sources + [source]).bytesize <= 65_536
                raise Research::Error.new("agent_evidence_budget_exceeded")
              end
              cache[signature] = source
              sources << source
              @observations << source
            end
            @events.emit("tool.completed", "name" => call.name, "source_id" => source["source_id"])
            history << { "type" => "function_call_output", "call_id" => call.id, "output" => JSON.generate(source) }
          end
        end
        raise Research::Error.new("agent_step_limit")
      rescue Research::Error => error
        fail!(error)
        raise
      rescue ActiveRecord::ActiveRecordError, IOError => error
        Rails.logger.warn("Research agent #{@run&.id} local failure type=#{error.class.name}")
        failure = Research::Error.new("agent_local_failure")
        fail!(failure)
        raise failure, cause: nil
      ensure
        close_tools!
        @model.close if @model.respond_to?(:close)
      end

      def cancel!
        @cancellation.cancel!
        @tools&.cancel!
      end

      private

      def claim!
        ApplicationRecord.transaction do
          @user.lock!
          ApplicationRecord.connection.execute("SELECT pg_advisory_xact_lock(#{ResearchEmbeddingAttempt::GLOBAL_LOCK})")
          raise Research::Error.new("agent_run_replay_requires_review") if ResearchAgentRun.exists?(user: @user, request_key: @request_key)
          if ResearchAgentRun.where(state: "running").count >= 2 || ResearchAgentRun.exists?(user: @user, state: "running")
            raise Research::Error.new("agent_concurrency_limit")
          end
          @run = ResearchAgentRun.create!(user: @user, request_key: @request_key, query_digest: Digest::SHA256.hexdigest(@query),
            selectors: @selectors, provider: @selectors["evidence_mode"] == "fixture" ? "fixture" : "openai",
            model: @selectors["evidence_mode"] == "fixture" ? "original-fixture-v1" : MODEL,
            prompt_version: PROMPT_VERSION, deadline_at: [Time.current + 90.seconds, @evidence&.request&.deadline_at].compact.min)
        end
      end

      def check!(cleanup: false)
        @cancellation.check! unless cleanup
        @user.with_lock do
          @run.reload
          raise Research::Error.new("agent_deadline") if !cleanup && @run.deadline_at <= Time.current
          raise Research::Error.new("agent_not_running") unless cleanup || @run.state == "running"
          settings = @policy.check!(@run)
          fingerprints = { "policy" => Digest::SHA256.hexdigest(JSON.generate(settings.sort.to_h)) }
          if @run.provider != "fixture"
            key = ENV["OPENAI_API_KEY"].to_s.strip
            unless key.present? && key.valid_encoding? && key.length <= 4096 && !key.match?(/\s/)
              raise Research::Error.new("openai_credentials_required")
            end
            fingerprints["openai"] = Digest::SHA256.hexdigest(key)
            if %w[live_mcp mixed].include?(@selectors["evidence_mode"])
              unless EquiblesConnection.encryption_configured? && @user.equibles_connection
                raise Research::Error.new("equibles_credentials_required")
              end
              fingerprints["equibles"] = Digest::SHA256.hexdigest(@user.equibles_connection.reload.read_attribute_before_type_cast(:api_key).to_s)
            end
          end
          if @run.credential_fingerprints.present? && @run.credential_fingerprints != fingerprints
            raise Research::Error.new("agent_credentials_or_policy_changed")
          end
          @run.update!(credential_fingerprints: fingerprints) if @run.credential_fingerprints.blank?
          if !cleanup && @evidence
            @evidence.status == "ready" ? @evidence.recheck! : @evidence.check_request!
          end
          if !cleanup && @observations.any? { |source|
              Time.iso8601(source.fetch("fresh_until")) <= Time.current || Time.iso8601(source.fetch("expires_at")) <= Time.current
            }
            raise Research::Error.new("agent_live_evidence_stale_or_expired")
          end
        end
        remaining = @run.deadline_at - Time.current
        raise Research::Error.new("agent_deadline") if !cleanup && remaining <= 0
        remaining
      end

      def before_protocol!(method)
        ApplicationRecord.connection_pool.with_connection do
          remaining = check!(cleanup: %w[notifications/cancelled session/close].include?(method))
          raise Research::Error.new("agent_deadline") if remaining <= 0
          @user.with_lock do
            settings = @policy.check!(@run)
            SourceQuota.reserve!(@run, allocation: settings.fetch("daily_source_requests"), limit: 16)
          end
        end
        @run.deadline_at - Time.current
      end

      def local_sources
        return [] unless @evidence
        request = @evidence.request.reload
        selected = request.selectors
        year = request.latest_event["fiscal_year"] || selected["fiscal_year"]
        quarter = request.latest_event["fiscal_quarter"] || selected["fiscal_period"]&.delete_prefix("Q")&.to_i
        unless request.user_id == @user.id && selected["listing_identity"] == @selectors["listing_identity"] &&
               [year, quarter, selected["mode"]] == [@selectors["fiscal_year"], @selectors["fiscal_quarter"], @selectors["query_mode"]]
          raise Research::Error.new("agent_evidence_scope_mismatch")
        end
        @user.with_lock do
          raise Research::Error.new("evidence_already_used_by_run") if request.agent_run_id && request.agent_run_id != @run.id
          request.update!(agent_run: @run)
          @run.update!(tool_calls: request.source_requests)
        end
        return [] unless @evidence.status == "ready" && %w[retained mixed].include?(@selectors["evidence_mode"])
        JSON.parse(@evidence.context_json).fetch("sources").map { |source| source.merge("origin" => "retained") }
      end

      def latest_event
        return unless @selectors["query_mode"] == "latest_earnings"
        @evidence.check_request!
        event = @evidence.request.latest_event
        raise Research::Error.new("latest_event_unavailable") unless event.present? && event["reason"].nil? && event["event_at"]
        event
      end

      def model_step(attempt, history, definitions)
        check!
        @model.prepare!
        @events.emit("model.started", "step" => attempt.step)
        @user.with_lock { attempt.update!(state: "dispatched") }
        response = @model.call(input: history, tools: definitions, output_tokens: attempt.reserved_output_tokens,
          timeout: @run.deadline_at - Time.current, request_key: "research-model-#{attempt.id}",
          check: method(:check!), forbidden: @forbidden)
        attempt.reconcile!(usage: response.usage)
        unless response.usage.input_tokens <= attempt.reserved_input_tokens &&
               response.usage.output_tokens <= attempt.reserved_output_tokens
          raise Research::Error.new("model_usage_exceeded_reservation")
        end
        check!
        @events.emit("model.completed", "step" => attempt.step, "input_tokens" => response.usage.input_tokens,
          "output_tokens" => response.usage.output_tokens)
        response
      rescue ProviderError => error
        attempt.reconcile!(usage: error.usage, error_code: error.code) if attempt.reload.state == "dispatched"
        raise
      rescue Research::Error => error
        if attempt.reload.state == "reserved"
          @user.with_lock { attempt.update!(state: "released", error_code: error.code) }
        elsif attempt.state == "dispatched"
          attempt.reconcile!(error_code: error.code)
        end
        raise
      end

      def publish!(result)
        publisher = ->(value) do
          check!
          @run.lock!
          @user.equibles_connection&.lock! if @run.provider != "fixture"
          check!
          @publisher&.call(value)
          @run.update!(state: "completed")
        end
        if @evidence&.status == "ready"
          @evidence.dispatch!(publisher: publisher) { result }
        else
          @user.with_lock { publisher.call(result) }
        end
      end

      def fail!(error)
        return unless @run&.persisted?
        completed = false
        @user.with_lock do
          @run.reload
          completed = @run.state == "completed"
          @run.update!(state: completed ? "completed" : (error.code == "agent_cancelled" ? "cancelled" : "failed"), error_code: error.code)
        end
        begin
          @events&.emit(error.code == "agent_cancelled" ? "run.cancelled" : "run.failed", "code" => error.code) unless completed
        rescue IOError
          Rails.logger.warn("Research agent #{@run.id} failure event delivery failed")
        end
        Rails.logger.warn("Research agent #{@run.id} rejected code=#{error.code}")
      end

      def close_tools!
        original_error = $!
        tools = @tools
        @tools = nil
        tools&.close
      rescue Research::Error => error
        Rails.logger.warn("Research agent #{@run&.id} session cleanup rejected code=#{error.code}")
        raise unless original_error
      end
    end
  end
end
