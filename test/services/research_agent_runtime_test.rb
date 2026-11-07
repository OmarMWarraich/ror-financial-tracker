require "test_helper"

class ResearchAgentRuntimeTest < ActiveSupport::TestCase
  self.use_transactional_tests = false
  Agent = Research::Agent

  setup do
    @users = []
    @user = owner
  end

  teardown do
    @users.each do |user|
      user.with_lock do
        ResearchModelAttempt.where(user: user).delete_all
        ResearchEmbeddingAttempt.where(user: user).delete_all
        ResearchRetrieval.where(user: user).delete_all
        ResearchIngestion.where(user: user).delete_all
        ResearchDocument.where(user: user).update_all(current_revision_id: nil)
        ResearchEmbedding.where(user: user).delete_all
        ResearchPassage.where(user: user).delete_all
        ResearchRevision.where(user: user).delete_all
        ResearchDocument.where(user: user).delete_all
        ResearchEmbeddingSpace.where(user: user).delete_all
        ResearchAgentRun.where(user: user).delete_all
      end
      user.destroy!
    end
  end

  test "native fixture loop reserves reconciles tools and emits only guarded attributed final text" do
    events = []
    published = []
    runtime = build(events: events.method(:<<), publisher: ->(result) { published << result })
    result = runtime.call
    assert_equal "completed", result.status
    assert_equal 3, result.usage.size
    assert_equal 2, runtime.run.reload.tool_calls
    assert_equal 0, runtime.run.source_requests
    assert_equal "original-fixture-v1", runtime.run.model
    assert_equal 0, runtime.run.model_attempts.sum(:actual_cost_nanos)
    assert_equal [result], published
    assert result.sources.all? { |source| source["synthetic"] && source["origin"] == "fixture" }
    assert_includes result.text, result.sources.last["source_id"]
    assert_equal (1..events.size).to_a, events.map { |event| event["sequence"] }
    assert events.all? { |event| event["version"] == 1 && event["run_id"] == runtime.run.id }
    assert_equal "run.completed", events.last["type"]
    assert_equal result.text, events.select { |event| event["type"] == "text.delta" }.map { |event| event.dig("data", "text") }.join
    assert_nil runtime.run.attributes["query"]
    assert_nil runtime.run.attributes["answer"]
  end

  test "live inference and MCP remain default off and populated environment alone does not authorize" do
    runtime = build(evidence_mode: "live_mcp", listing_identity: "US:ALPHA")
    error = assert_raises(Research::Error) { runtime.call }
    assert_equal "agent_permission_required", error.code
    assert_empty runtime.run.model_attempts
    assert_equal "failed", runtime.run.reload.state
  end

  test "writes and malformed tool calls abort before execution while preserving known model usage" do
    fake = ScriptedModel.new { |_input, _index| Agent::ToolCall.new(id: "original_call", name: "DeleteMyPortfolio", arguments: {}) }
    runtime = build(model: fake)
    error = assert_raises(Research::Error) { runtime.call }
    assert_equal "agent_tool_not_authorized", error.code
    assert_equal 0, runtime.run.reload.tool_calls
    assert_equal "settled", runtime.run.model_attempts.first.state
    assert_equal 0, fake.transactions
  end

  test "unknown usage blocks new paid requests and existing embedding budgets" do
    fake = ScriptedModel.new { raise Agent::ProviderError.new("model_timeout") }
    runtime = build(model: fake)
    assert_raises(Agent::ProviderError) { runtime.call }
    assert_equal "uncertain", runtime.run.model_attempts.first.state
    another = new_run(provider: "openai")
    error = assert_raises(Research::Error) { ResearchModelAttempt.reserve!(another, input_tokens: 10, output_tokens: 10) }
    assert_equal "uncertain_usage_requires_review", error.code
    ingestion = ResearchIngestion.create!(user: @user, request_key: SecureRandom.uuid, provider: "synthetic",
      source_kind: "earnings_brief", listing_identity: "SYNTH:ALPHA", fiscal_year: 2026, fiscal_quarter: 3,
      fixture_version: "v1", state: "pending",
      space: space, generation: 1)
    assert_raises(Research::Error) { ResearchEmbeddingAttempt.reserve!(ingestion, tokens: 10, batch_key: "original", paid: true) }
  end

  test "four-step input output spend and shared daily budgets fail closed" do
    run = new_run(provider: "openai")
    assert_raises(Research::Error) { ResearchModelAttempt.reserve!(run, input_tokens: 10_001, output_tokens: 1) }
    first = ResearchModelAttempt.reserve!(run, input_tokens: 6000, output_tokens: 4096)
    first.update!(state: "dispatched")
    first.reconcile!(usage: Agent::Usage.new(input_tokens: 6000, output_tokens: 4090))
    assert_raises(Research::Error) { ResearchModelAttempt.reserve!(run, input_tokens: 6001, output_tokens: 1) }
    assert_raises(Research::Error) { ResearchModelAttempt.reserve!(run, input_tokens: 1, output_tokens: 7) }
    assert_equal 6000 * 750 + 4090 * 4500, first.actual_cost_nanos
    first.update!(actual_cost_nanos: 499_999_999)
    error = assert_raises(Research::Error) { ResearchModelAttempt.reserve!(run, input_tokens: 1, output_tokens: 1) }
    assert_equal "agent_spend_budget_exceeded", error.code
  end

  test "cancellation and deadline abort before publication without releasing dispatched uncertainty" do
    cancellation = Agent::Cancellation.new
    fake = ScriptedModel.new do
      cancellation.cancel!
      raise Agent::ProviderError.new("agent_cancelled", usage: Agent::Usage.new(input_tokens: 5, output_tokens: 1))
    end
    runtime = build(model: fake, cancellation: cancellation, publisher: ->(_) { flunk "must not publish" })
    error = assert_raises(Research::Error) { runtime.call }
    assert_equal "agent_cancelled", error.code
    assert_equal "cancelled", runtime.run.reload.state
    assert_equal "settled", runtime.run.model_attempts.first.state
    fake = ScriptedModel.new do
      travel 2.minutes
      Agent::ToolCall.new(id: "event", name: "GetEarningsCallEvent",
        arguments: { "ticker" => "ALPHA", "fiscalYear" => 2026, "fiscalQuarter" => 3 })
    end
    runtime = build(model: fake)
    error = assert_raises(Research::Error) { runtime.call }
    assert_equal "agent_deadline", error.code
    assert_equal 0, runtime.run.reload.tool_calls
  end

  test "charged and fixture request keys cannot silently replay or switch provider" do
    key = SecureRandom.uuid
    build(request_key: key).call
    error = assert_raises(Research::Error) { build(request_key: key).call }
    assert_equal "agent_run_replay_requires_review", error.code
    assert_equal 1, ResearchAgentRun.where(user: @user).count
  end

  test "the same tool and arguments reuse evidence rather than silently charging a duplicate" do
    fake = ScriptedModel.new do |input, index|
      if index < 2
        Agent::ToolCall.new(id: "call_#{index}", name: "GetEarningsCallEvent",
          arguments: { "ticker" => "ALPHA", "fiscalYear" => 2026, "fiscalQuarter" => 3 })
      else
        source = JSON.parse(input.select { |item| item["type"] == "function_call_output" }.last["output"])
        "Original event metadata [#{source['source_id']}]"
      end
    end
    runtime = build(model: fake)
    result = runtime.call
    assert_equal 1, runtime.run.reload.tool_calls
    assert_equal 1, result.sources.size
    assert_equal 3, runtime.run.model_attempts.count
  end

  test "retained current and as-of contexts use guarded M3 evidence without implicit MCP" do
    %w[current as_of].each do |mode|
      evidence = retained_evidence(mode: mode)
      fake = ScriptedModel.new do |input|
        sources = JSON.parse(input.first.fetch("content")).fetch("evidence")
        assert_equal ["retained"], sources.map { |source| source["origin"] }.uniq
        "Original retained fixture [#{sources.first.fetch('source_id')}]"
      end
      with_model_marker do
        runtime = build(model: fake, policy: ApprovedFixturePolicy.new, evidence: evidence,
          evidence_mode: "retained", query_mode: mode, tools_factory: ->(*) { flunk "no implicit MCP discovery" })
        result = runtime.call
        assert_equal "completed", result.status
        assert_equal runtime.run.id, evidence.request.reload.agent_run_id
        assert_equal 1, result.usage.size
        assert_equal 0, runtime.run.reload.tool_calls
        assert_equal 0, fake.transactions
      end
    end
  end

  test "retained evidence revoked during inference cannot publish and known usage settles" do
    evidence = retained_evidence
    fake = ScriptedModel.new do |input|
      ResearchDocument.where(user: @user).update_all(revoked_at: Time.current)
      source = JSON.parse(input.first.fetch("content")).fetch("evidence").first
      "Original revoked fixture [#{source.fetch('source_id')}]"
    end
    events = []
    with_model_marker do
      runtime = build(model: fake, policy: ApprovedFixturePolicy.new, evidence: evidence,
        evidence_mode: "retained", events: events.method(:<<), publisher: ->(_) { flunk "revoked evidence cannot publish" })
      assert_raises(Research::Error) { runtime.call }
      assert_equal "failed", runtime.run.reload.state
      assert_equal "settled", runtime.run.model_attempts.first.state
      assert_empty events.select { |event| event["type"] == "text.delta" }
    end
  end

  test "scope mismatch and stale-only retained evidence never invoke inference" do
    evidence = retained_evidence
    with_model_marker do
      runtime = build(evidence: evidence, evidence_mode: "retained", fiscal_quarter: 2, policy: ApprovedFixturePolicy.new)
      assert_equal "agent_evidence_scope_mismatch", assert_raises(Research::Error) { runtime.call }.code
      ResearchRevision.where(user: @user).update_all(fresh_until: Time.current - 1.second)
      stale = Research::Retriever.new(user: @user, space: evidence.request.space, query: "revenue",
        request_key: SecureRandom.uuid, listing_identity: "SYNTH:ALPHA", fiscal_year: 2026, fiscal_period: "Q3").call
      assert_equal "stale_only", stale.status
      runtime = build(evidence: stale, evidence_mode: "retained", policy: ApprovedFixturePolicy.new)
      result = runtime.call
      assert_equal "stale_only", result.status
      assert_nil result.text
      assert_empty runtime.run.model_attempts
    end
  end

  test "live-only and mixed modes preserve injected fixture origins and recheck freshness" do
    EquiblesConnection.create!(user: @user, api_key: "original-offline-source-marker")
    @user.reload
    %w[live_mcp mixed].each do |mode|
      evidence = mode == "mixed" ? retained_evidence : nil
      fake = ScriptedModel.new do |input, index|
        if index.zero?
          Agent::ToolCall.new(id: "original_event", name: "GetEarningsCallEvent",
            arguments: { "ticker" => "ALPHA", "fiscalYear" => 2026, "fiscalQuarter" => 3 })
        else
          "Original injected fixture [#{JSON.parse(input.last.fetch('output')).fetch('source_id')}]"
        end
      end
      with_model_marker do
        runtime = build(evidence: evidence, evidence_mode: mode, policy: ApprovedFixturePolicy.new,
          model: fake, tools_factory: ->(registry, _) { Agent::FixtureTools.new(registry) })
        result = runtime.call
        assert_equal mode == "mixed" ? %w[retained fixture] : ["fixture"], result.sources.map { |source| source["origin"] }
        assert result.sources.all? { |source| source["synthetic"] }
      end
    end
    fake = ScriptedModel.new do |input, index|
      if index.zero?
        Agent::ToolCall.new(id: "original_event", name: "GetEarningsCallEvent",
          arguments: { "ticker" => "ALPHA", "fiscalYear" => 2026, "fiscalQuarter" => 3 })
      else
        travel 2.seconds
        "Original expired fixture [#{JSON.parse(input.last.fetch('output')).fetch('source_id')}]"
      end
    end
    with_model_marker do
      runtime = build(evidence_mode: "live_mcp", policy: ApprovedFixturePolicy.new(freshness: 1),
        model: fake, tools_factory: ->(registry, _) { Agent::FixtureTools.new(registry) })
      assert_equal "agent_live_evidence_stale_or_expired", assert_raises(Research::Error) { runtime.call }.code
      assert runtime.run.model_attempts.all? { |row| row.state == "settled" }
    end
  end

  test "fourth-step tool requests do not spend on evidence that cannot reach another model step" do
    fake = ScriptedModel.new do |_, index|
      Agent::ToolCall.new(id: "original_#{index}", name: index == 3 ? "GetEarningsBrief" : "GetEarningsCallEvent",
        arguments: { "ticker" => "ALPHA", "fiscalYear" => 2026, "fiscalQuarter" => 3 }.merge(index == 3 ? { "limit" => 1 } : {}))
    end
    runtime = build(model: fake)
    assert_equal "agent_step_limit", assert_raises(Research::Error) { runtime.call }.code
    assert_equal 4, runtime.run.model_attempts.count
    assert_equal 1, runtime.run.reload.tool_calls
  end

  test "publisher and delivery errors surface without corrupting publication state" do
    runtime = build(publisher: ->(_) { raise ActiveRecord::RecordInvalid.new(@user) })
    assert_equal "agent_local_failure", assert_raises(Research::Error) { runtime.call }.code
    assert_equal "failed", runtime.run.reload.state
    assert runtime.run.model_attempts.all? { |row| row.state == "settled" }
    runtime = build(events: ->(event) { raise IOError, "original offline delivery failure" if event["type"] == "text.delta" })
    assert_equal "agent_local_failure", assert_raises(Research::Error) { runtime.call }.code
    assert_equal "completed", runtime.run.reload.state
    assert_equal "agent_local_failure", runtime.run.error_code
  end

  test "owner and global active-run ceilings reject admission before model or tool work" do
    first = new_run(provider: "openai")
    assert_equal "agent_concurrency_limit", assert_raises(Research::Error) { build.call }.code
    first.update!(state: "failed")
    second_owner = owner
    third_owner = owner
    new_run(provider: "openai")
    ResearchAgentRun.create!(user: second_owner, request_key: SecureRandom.uuid, query_digest: "b" * 64, selectors: {},
      provider: "openai", model: Agent::MODEL, prompt_version: Agent::PROMPT_VERSION, deadline_at: Time.current + 90.seconds)
    assert_equal "agent_concurrency_limit", assert_raises(Research::Error) { build(user: third_owner).call }.code
    assert_empty ResearchModelAttempt.where(user: @users)
  end

  def build(**options)
    Agent::Runtime.new(**{ user: @user, query: "Summarize original fictional Alpha earnings.", request_key: SecureRandom.uuid,
      listing_identity: "SYNTH:ALPHA", fiscal_year: 2026, fiscal_quarter: 3 }.merge(options))
  end

  def owner
    User.create!(email: "agent-#{SecureRandom.uuid}@example.test", password: "original-test-password").tap { |user| @users << user }
  end

  def new_run(provider:)
    ResearchAgentRun.create!(user: @user, request_key: SecureRandom.uuid, query_digest: "a" * 64, selectors: {},
      provider: provider, model: Agent::MODEL, prompt_version: Agent::PROMPT_VERSION, deadline_at: Time.current + 90.seconds)
  end

  def space
    ResearchEmbeddingSpace.create!(user: @user, provider: "synthetic", model: "fixture-1536", model_version: "sha256-v1",
      dimensions: 1536, distance: "cosine", preprocessing_version: Research::Chunker::PREPROCESSING,
      chunker_version: Research::Chunker::VERSION, state: "building")
  end

  def retained_evidence(mode: "current")
    now = Time.current
    embedding_space = @evidence_space ||= space
    document = @user.research_documents.create!(provider: "synthetic", source_kind: "earnings_transcript",
      source_id: SecureRandom.uuid, listing_identity: "SYNTH:ALPHA", instrument_identity: "synthetic:SYNTH:ALPHA",
      fiscal_year: 2026, fiscal_period: "Q3", citation_url: "https://example.invalid/original-fixture",
      entitlement_reference: "original-public-fixture-v1", rights_expires_at: now + 30.days)
    temporal = Research::TemporalEvidence.source({ metadata: {}, event_at: now - 6.days, published_at: now - 5.days,
      known_at: now - 5.days, received_at: now - 1.day }, provider: "synthetic")
    normalized = Research::Chunker.normalize([{ "text" => "Original fictional Alpha revenue and cloud research fixture." }], metadata: {})
    revision = document.revisions.create!(normalized.merge(temporal[:values]).merge(user: @user,
      temporal_metadata: temporal[:metadata], expires_at: now + 7.days, fresh_until: now + 1.hour,
      indexed_at: now, verified_at: now, index_state: "ready"))
    document.update!(current_revision: revision)
    passage = revision.passages.create!(Research::Chunker.new.call(revision).first.merge(user: @user,
      preprocessing_version: Research::Chunker::PREPROCESSING, chunker_version: Research::Chunker::VERSION))
    embedding_space.embeddings.create!(user: @user, passage: passage, embedding: Array.new(1536, 0.0).tap { |values| values[0] = 1.0 })
    embedding_space.activate! if embedding_space.state == "building"
    Research::Retriever.new(user: @user, space: embedding_space, query: "revenue", request_key: SecureRandom.uuid,
      listing_identity: "SYNTH:ALPHA", fiscal_year: 2026, fiscal_period: "Q3",
      mode: mode, as_of: mode == "as_of" ? (now - 2.days).utc.iso8601 : nil).call
  end

  def with_model_marker
    previous = ENV["OPENAI_API_KEY"]
    ENV["OPENAI_API_KEY"] = "original-offline-model-marker"
    yield
  ensure
    previous ? ENV["OPENAI_API_KEY"] = previous : ENV.delete("OPENAI_API_KEY")
  end

  class ApprovedFixturePolicy
    def initialize(freshness: 600)
      @settings = { "source_kinds" => %w[earnings_brief earnings_transcript],
        "mcp_tools" => Research::Agent::ToolRegistry::FIELDS.keys, "freshness_seconds" => freshness,
        "retention_seconds" => 3600, "expires_at" => (Time.current + 1.hour).utc.iso8601,
        "daily_source_requests" => 30 }
    end

    def check!(_)
      @settings
    end
  end

  class ScriptedModel
    attr_reader :transactions

    def initialize(&script)
      @script, @calls, @transactions = script, 0, 0
    end

    def prepare!
    end

    def call(input:, **_)
      @transactions += 1 if ApplicationRecord.connection.transaction_open?
      result = @script.call(input, @calls)
      @calls += 1
      calls = result.is_a?(Research::Agent::ToolCall) ? [result] : []
      output = calls.map { |call| { "type" => "function_call", "call_id" => call.id, "name" => call.name,
        "arguments" => JSON.generate(call.arguments) } }
      Research::Agent::ModelResult.new(text: result.is_a?(String) ? result : "", tool_calls: calls, output: output,
        usage: Research::Agent::Usage.new(input_tokens: 5, output_tokens: 1))
    end
  end
end
