require "test_helper"

class ResearchAgentLifecycleTest < ActiveSupport::TestCase
  self.use_transactional_tests = false
  Agent = Research::Agent

  setup do
    @users = []
    @user = owner
  end

  teardown do
    @users.each do |user|
      user.with_lock do
        ResearchToolAttempt.where(user: user).delete_all
        ResearchMessage.where(user: user).delete_all
        ResearchModelAttempt.where(user: user).delete_all
        ResearchAgentRun.where(user: user).delete_all
        ResearchConversation.where(user: user).delete_all
        ResearchSourceUsage.where(user: user).delete_all
      end
      user.equibles_connection&.destroy!
      user.destroy!
    end
  end

  test "durable original fixture queues then completes encrypted messages and attributed receipts" do
    run = submit
    assert_equal "queued", run.state
    assert_equal Agent::Lifecycle::WORKFLOW, run.workflow_version
    raw = ApplicationRecord.connection.select_value("SELECT content FROM research_messages WHERE run_id = #{run.id}")
    assert_not_includes raw, "Original fictional"
    assert_equal run.id, submit(request_key: run.request_key).id
    assert_equal 1, ResearchAgentRun.where(user: @user).count
    result = Agent::Execution.call(run)
    assert_equal "completed", run.reload.state
    assert_equal result.text, run.messages.find_by!(role: "assistant").readable_content!
    assert_equal 2, run.tool_attempts.count
    assert run.tool_attempts.all? { |receipt| receipt.state == "settled" && receipt.arguments_digest.length == 64 }
    assert_equal 0, Agent::Spend.conversation(run.conversation)
    assert_nil run.lease_token
    assert run.finished_at
    assert_equal 2, Agent::Lifecycle.messages!(user: @user, conversation_id: run.conversation_id).size
    assert_raises(ActiveRecord::RecordNotFound) {
      Agent::Lifecycle.messages!(user: owner, conversation_id: run.conversation_id)
    }
  end

  test "deduplication rejects changed submission and owner cannot stop another run" do
    run = submit
    assert_equal "agent_submission_conflict", assert_raises(Research::Error) {
      submit(request_key: run.request_key, query: "A changed original question")
    }.code
    assert_raises(ActiveRecord::RecordNotFound) { Agent::Lifecycle.stop!(user: owner, run_id: run.id) }
    Agent::Lifecycle.stop!(user: @user, run_id: run.id)
    assert_equal "cancelled", run.reload.state
    assert_equal "incomplete", run.messages.find_by!(role: "assistant").state
    assert_empty run.model_attempts
    assert_equal "agent_run_replay_requires_review", assert_raises(Research::Error) { Agent::Execution.call(run) }.code
  end

  test "user limits only lower operator and conversation caps and apply outside model" do
    assert_equal "invalid_agent_limits", assert_raises(Research::Error) { submit(preferences: { "steps" => 5 }) }.code
    run = submit(preferences: { "steps" => 1, "tools" => 1, "turns" => 1 })
    assert_equal "agent_step_limit", assert_raises(Research::Error) { Agent::Execution.call(run) }.code
    assert_equal 1, run.model_attempts.count
    assert_equal 0, run.reload.tool_calls
    assert_equal "conversation_turn_limit", assert_raises(Research::Error) { submit(conversation: run.conversation) }.code
    assert_equal "invalid_agent_limits", assert_raises(Research::Error) {
      submit(conversation: run.conversation, preferences: { "steps" => 2 })
    }.code
  end

  test "stop between streamed deltas retains unknown usage and does not persist unsafe partial answer" do
    run = submit
    model = StreamingStop.new(run, known: false)
    assert_equal "agent_cancelled", assert_raises(Research::Error) { Agent::Execution.call(run, model: model) }.code
    assert_equal "cancelled", run.reload.state
    assert_equal "uncertain", run.model_attempts.first.state
    answer = run.messages.find_by!(role: "assistant")
    assert_equal "incomplete", answer.state
    assert_nil answer.content
    assert_equal 0, model.transactions
    @user = owner
    run = submit
    assert_equal "agent_cancelled", assert_raises(Research::Error) {
      Agent::Execution.call(run, model: StreamingStop.new(run, known: true))
    }.code
    assert_equal "settled", run.model_attempts.first.state
  end

  test "lease crash recovery retains ambiguous spend and fences old worker without paid replay" do
    run = paid_run
    token = Agent::Lifecycle.claim!(run)
    attempt = ResearchModelAttempt.reserve!(run, input_tokens: 100, output_tokens: 100)
    attempt.update!(state: "dispatched")
    travel 21.seconds do
      Agent::Lifecycle.recover!
      assert_equal "interrupted", run.reload.state
      assert_equal "uncertain", attempt.reload.state
      assert_equal 525_000, Agent::Spend.cost(user_id: @user.id)
      assert_equal "agent_lease_lost", assert_raises(Research::Error) { Agent::Lifecycle.check_lease!(run, token) }.code
      assert_equal "agent_run_replay_requires_review", assert_raises(Research::Error) { Agent::Execution.call(run) }.code
      assert_equal 1, run.model_attempts.count
    end
    attempt.reconcile!(usage: Agent::Usage.new(input_tokens: 100, output_tokens: 20))
    assert_equal "settled", attempt.reload.state
    assert_equal 165_000, attempt.actual_cost_nanos
    assert_equal "interrupted", run.reload.state
  end

  test "atomic worker claim admits exactly one claimant across tabs and jobs" do
    run = submit
    gate = Queue.new
    workers = 2.times.map do
      Thread.new do
        ApplicationRecord.connection_pool.with_connection do
          gate.pop
          begin
            Agent::Lifecycle.claim!(ResearchAgentRun.find(run.id))
          rescue Research::Error => error
            error.code
          end
        end
      end
    end
    2.times { gate << true }
    results = workers.map(&:value)
    assert_equal 1, results.count { |value| value.match?(/\A[0-9a-f-]{36}\z/) }
    assert_equal 1, results.count("agent_run_replay_requires_review")
    assert_empty run.model_attempts
  end

  test "queued run reservations share embedding daily and lifetime conversation spend without double counting" do
    run = paid_run
    assert_equal 50_000_000, Agent::Spend.cost(user_id: @user.id)
    token = Agent::Lifecycle.claim!(run)
    attempt = ResearchModelAttempt.reserve!(run, input_tokens: 100, output_tokens: 100)
    assert_equal 50_000_000, Agent::Spend.cost(user_id: @user.id)
    attempt.update!(state: "dispatched")
    attempt.reconcile!(usage: Agent::Usage.new(input_tokens: 10, output_tokens: 10))
    assert_equal 50_000_000, Agent::Spend.conversation(run.conversation)
    assert Agent::Lifecycle.check_lease!(run, token)
    Agent::Lifecycle.terminal!(run, state: "failed", code: "original_offline_end")
    assert_equal 52_500, Agent::Spend.cost(user_id: @user.id)
    assert_equal 52_500, Agent::Spend.conversation(run.conversation)
    other = paid_run(conversation: run.conversation, preferences: { "conversation_cost_nanos" => 1 })
    assert_equal "agent_spend_budget_exceeded", assert_raises(Research::Error) {
      Agent::Lifecycle.claim!(other)
      ResearchModelAttempt.reserve!(other, input_tokens: 1, output_tokens: 1)
    }.code
  end

  test "UTC rollover and pricing changes explicitly stop rather than silently switching prices or replaying" do
    run = paid_run
    token = Agent::Lifecycle.claim!(run)
    changed = Agent::Limits.pricing.merge("input_nanos" => 751)
    Agent::Limits.stub(:pricing, changed) do
      assert_equal "model_pricing_changed", assert_raises(Research::Error) { Agent::Lifecycle.check_lease!(run, token) }.code
    end
    travel_to(Time.current.utc.end_of_day + 1.second) do
      run.update!(lease_until: Time.current + 20.seconds)
      assert_equal "agent_budget_window_changed", assert_raises(Research::Error) { Agent::Lifecycle.check_lease!(run, token) }.code
    end
  end

  test "expired queue and encrypted chat are explicit and recovery redacts bodies without pretending backups erased" do
    run = submit
    travel 91.seconds do
      Agent::Lifecycle.recover!
      assert_equal "failed", run.reload.state
      assert_equal "agent_queue_deadline", run.error_code
      assert_empty run.model_attempts
    end
    travel 2.days do
      assert_equal "chat_retention_expired", assert_raises(Research::Error) { run.messages.first.readable_content! }.code
      Agent::Lifecycle.recover!
      assert run.messages.reload.all? { |message| message.state == "redacted" && message.content.nil? }
    end
  end

  test "quota capacity includes REST MCP and same-key owners and never raises allowance from provider headers" do
    key = "original-offline-shared-marker"
    first = EquiblesConnection.create!(user: @user, api_key: key, requests_used: 5, quota_date: Time.current.utc.to_date)
    second_owner = owner
    second = EquiblesConnection.create!(user: second_owner, api_key: key, requests_used: 5, quota_date: Time.current.utc.to_date)
    settings = quota_settings
    assert_equal 10, Research::SourceQuota.group_used(first)
    Research::SourceQuota.check_capacity!(first, settings: settings, additional: 16)
    assert_equal "source_request_budget_exceeded", assert_raises(Research::Error) {
      Research::SourceQuota.check_capacity!(first, settings: settings, additional: 21)
    }.code
    unknown = settings.except("quota_reviewed_until")
    assert_equal "source_budget_unknown", assert_raises(Research::Error) {
      Research::SourceQuota.check_capacity!(first, settings: unknown, additional: 1)
    }.code
    run = paid_run(source: first, evidence_mode: "live_mcp")
    policy = Struct.new(:settings) { def check!(_) = settings }.new(settings)
    Agent::Policy.stub(:new, policy) do
      Research::SourceQuota.observe!(run, 200, { "X-RateLimit-Remaining" => "2", "Authorization" => "not-retained" })
      Research::SourceQuota.observe!(run, 200, { "X-RateLimit-Remaining" => "30" })
      assert_equal 2, first.reload.quota_observation["remaining"]
      assert_not_includes first.quota_observation.to_json, "not-retained"
      assert_equal "source_request_budget_exceeded", assert_raises(Research::Error) {
        Research::SourceQuota.check_capacity!(second, settings: settings, additional: 1)
      }.code
      Research::SourceQuota.observe!(run, 429, {})
      assert first.reload.quota_observation["blocked"]
    end
  end

  test "queue outages retain durable deduplication and retries never replay terminal work" do
    run = submit
    ResearchAgentJob.stub(:perform_async, ->(*) { raise RedisClient::CannotConnectError, "original offline outage" }) do
      assert_equal "research_queue_unavailable", assert_raises(Research::Error) { Agent::Lifecycle.enqueue!(run) }.code
    end
    assert_equal "queued", run.reload.state
    assert_equal "research_queue_unavailable", run.error_code
    assert_equal run.id, submit(request_key: run.request_key).id
    assert_equal 1, run.enqueue_attempts
    ResearchAgentJob.stub(:perform_async, ->(id) { assert_equal run.id, id; "original-offline-job" }) do
      3.times { Agent::Lifecycle.enqueue!(run) }
      assert_equal "agent_queue_retry_limit", assert_raises(Research::Error) { Agent::Lifecycle.enqueue!(run) }.code
    end
    assert_nil run.reload.error_code
    Agent::Lifecycle.stop!(user: @user, run_id: run.id)
    assert_equal "agent_not_queued", assert_raises(Research::Error) { Agent::Lifecycle.enqueue!(run) }.code
    assert_empty run.model_attempts
  end

  test "unsaved and foreign conversations are rejected before submission and paid gates stay off" do
    assert_equal "invalid_research_conversation", assert_raises(Research::Error) {
      submit(conversation: ResearchConversation.new(user: @user))
    }.code
    foreign = submit(user: owner).conversation
    assert_equal "invalid_research_conversation", assert_raises(Research::Error) { submit(conversation: foreign) }.code
    assert_equal "agent_permission_required", assert_raises(Research::Error) {
      submit(listing_identity: "US:ALPHA", evidence_mode: "live_mcp")
    }.code
    assert_empty @user.research_agent_runs
  end

  test "SQL rejects chat rewriting tool identity changes and same-owner cross-conversation links" do
    run = submit
    Agent::Execution.call(run)
    message = run.messages.find_by!(role: "user")
    assert_raises(ActiveRecord::StatementInvalid) { message.update_columns(content: "Rewritten original question") }
    assert_raises(ActiveRecord::StatementInvalid) { ResearchMessage.where(id: message.id).update_all(expires_at: Time.current + 2.days) }
    receipt = run.tool_attempts.first
    assert_raises(ActiveRecord::StatementInvalid) { ResearchToolAttempt.where(id: receipt.id).update_all(arguments_digest: "b" * 64) }
    other = submit
    assert_raises(ActiveRecord::InvalidForeignKey) {
      ResearchMessage.insert_all!([{ user_id: @user.id, conversation_id: run.conversation_id, run_id: other.id,
        role: "assistant", state: "complete", content: "Original mismatched message", expires_at: Time.current + 1.day }])
    }
    assert_raises(ActiveRecord::StatementInvalid) { run.update_columns(state: "queued") }
    assert_equal "completed", run.reload.state
  end

  test "shared source reservations serialize at exact capacity and credential rotation never erases consumed quota" do
    second_owner = owner
    connections = [
      EquiblesConnection.create!(user: @user, api_key: "original-shared-quota-key", requests_used: 14, quota_date: Time.current.utc.to_date),
      EquiblesConnection.create!(user: second_owner, api_key: "original-shared-quota-key", requests_used: 15, quota_date: Time.current.utc.to_date)
    ]
    requests = connections.map do |connection|
      connection.user.research_agent_runs.create!(request_key: SecureRandom.uuid, query_digest: "a" * 64, selectors: {},
        provider: "fixture", model: "original-fixture-v1", prompt_version: Agent::PROMPT_VERSION,
        state: "queued", deadline_at: Time.current + 90.seconds)
    end
    gate = Queue.new
    workers = requests.map do |request|
      Thread.new do
        ApplicationRecord.connection_pool.with_connection do
          gate.pop
          begin
            request.user.with_lock { Research::SourceQuota.reserve!(request, allocation: 30, limit: 16) }
            "reserved"
          rescue Research::Error => error
            error.code
          end
        end
      end
    end
    2.times { gate << true }
    assert_equal ["reserved", "source_request_budget_exceeded"], workers.map(&:value).sort
    assert_equal 30, Research::SourceQuota.group_used(connections.last.reload)
    connections.first.reload.update!(api_key: "original-rotated-quota-key")
    assert_equal 30, Research::SourceQuota.group_used(connections.last.reload)
    connections.first.destroy!
    assert_equal 30, Research::SourceQuota.group_used(connections.last.reload)
  end

  test "quote HTTP holds no database transaction and late old credentials cannot overwrite newer evidence or errors" do
    settings = { "approval_reference" => "original-offline-quote-approval", "subscription_verified" => true,
      "paid_quotes" => true, "automated_read" => true, "private_display" => true, "cache_storage" => true,
      "daily_request_budget" => 30, "retention_seconds" => 3600, "freshness_seconds" => 900 }
    entitlement = EquiblesEntitlement.new(@user, configuration: { "verified_users" => { @user.id.to_s => settings } })
    connection = EquiblesConnection.create!(user: @user, api_key: "original-quote-key")
    [false, true].each do |failure|
      connection.update!(last_attempt_at: nil)
      client = Object.new
      client.define_singleton_method(:snapshot) do |_ticker|
        raise "HTTP transaction unexpectedly open" if ApplicationRecord.connection.transaction_open?
        connection.reload.update!(api_key: "original-rotated-quote-#{failure}", last_attempt_at: Time.current + 1.second,
          snapshot: { "provider" => "original-newer-fixture" }, last_success_at: Time.current, last_error: nil)
        raise EquiblesClient::EvidenceError, "provider_unavailable" if failure
        { "provider" => "original-obsolete-fixture" }
      end
      assert_not EquiblesEvidenceRefresh.new(connection, entitlement: entitlement, client_factory: ->(*) { client }).call("AAPL")
      assert_equal "original-newer-fixture", connection.reload.snapshot["provider"]
      assert_nil connection.last_error
    end
  end

  def owner
    User.create!(email: "original-m5-#{SecureRandom.uuid}@example.test", password: "original-fixture-password").tap { |user| @users << user }
  end

  def submit(**options)
    Agent::Lifecycle.submit!(**{ user: @user, query: "Original fictional Alpha earnings research.",
      request_key: SecureRandom.uuid, listing_identity: "SYNTH:ALPHA", fiscal_year: 2026, fiscal_quarter: 3,
      enqueue: false }.merge(options))
  end

  def paid_run(conversation: nil, preferences: {}, source: nil, evidence_mode: "retained")
    limits = Agent::Limits.resolve(preferences)
    scope = { "listing_identity" => "US:ALPHA", "fiscal_year" => 2026, "fiscal_quarter" => 3,
      "query_mode" => "current", "evidence_mode" => evidence_mode }
    conversation ||= @user.research_conversations.create!(scope: scope, limits: limits, expires_at: Time.current + 1.day)
    @user.research_agent_runs.create!(conversation: conversation, request_key: SecureRandom.uuid, query_digest: "a" * 64,
      selectors: scope, limits: limits, pricing: Agent::Limits.pricing, workflow_version: Agent::Lifecycle::WORKFLOW,
      provider: "openai", model: Agent::MODEL, prompt_version: Agent::PROMPT_VERSION, state: "queued",
      budget_date: Time.current.utc.to_date, reserved_cost_nanos: 50_000_000, deadline_at: Time.current + 90.seconds,
      source_connection: source, reserved_source_requests: source ? 16 : 0)
  end

  def quota_settings
    { "quota_daily_capacity" => 30, "daily_source_requests" => 30, "external_usage_reserved_requests" => 0,
      "quota_reviewed_until" => (Time.current + 23.hours).utc.iso8601,
      "quota_header_semantics" => "utc_daily_requests_remaining" }
  end

  class StreamingStop
    attr_reader :transactions
    def initialize(run, known:)
      @run, @known, @transactions = run, known, 0
    end

    def prepare!
    end

    def call(check:, **_)
      @transactions += 1 if ApplicationRecord.connection.transaction_open?
      Agent::Lifecycle.stop!(user: @run.user, run_id: @run.id)
      if @known
        raise Agent::ProviderError.new("agent_cancelled", usage: Agent::Usage.new(input_tokens: 10, output_tokens: 1))
      end
      check.call
    end
  end
end
