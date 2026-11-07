require "minitest/autorun"
require "tempfile"
require "open3"
require "rbconfig"
require_relative "../../lib/project_knowledge"

class ProjectKnowledgeTest < Minitest::Test
  def setup
    @knowledge = ProjectKnowledge.new
  end

  def test_retrieves_alvis_and_transcription_aliases
    ["ALVIS", "what is ALVIS", "Elvis AI", "Alvish", "Equiples", "Equipables"].each do |query|
      result = @knowledge.search(query).first
      assert_equal "equibles-alvis", result["id"], query
      assert_equal "verified_fact", result["status"]
      assert_includes result["sources"], "https://equibles.com/docs/alvis"
    end
  end

  def test_live_market_dashboard_does_not_claim_cache_redistribution_or_ai_approval
    result = @knowledge.search("C01 dashboard").first
    assert_equal "equibles-market-dashboard", result["id"]
    assert_equal "implemented", result["status"]
    assert_includes result["summary"], "production remains denied"
    assert_includes result["summary"], "no background polling, OpenAI, trading or screener-price fallback"
    assert_includes result["summary"], "cap120/key/day"
    assert_includes result["summary"], "900000ms"
    assert_includes result["summary"], "date-only"
    assert_match(/exact named billing plan\/expiry/i, result["summary"])
    assert_includes result["sources"], "app/services/market_dashboard.rb"
  end

  def test_distinguishes_unverified_api_access_from_provider_fact
    result = @knowledge.search("ALVIS inference endpoint").first
    assert_equal "alvis-programmatic-access", result["id"]
    assert_equal "open_question", result["status"]
  end

  def test_m0_contract_is_planning_not_enabled_inference
    result = @knowledge.search("latest_earnings_v1 pilot ceilings").first
    assert_equal "m0-research-pilot-contract", result["id"]
    assert_equal "user_decision", result["status"]
    assert_includes result["summary"], "not runtime-implemented"
    assert_includes result["summary"], "no paid calls are authorized"
    assert_includes result["summary"], "baseline precedes vectors"
    assert_includes result["sources"], "README.md#m0-research-pilot-specification"
  end

  def test_m9_evaluation_reports_failed_baselines_and_separate_rollout_gates
    result = @knowledge.search("M9-07").first
    assert_equal "research-acceptance", result["id"]
    assert_equal "implemented", result["status"]
    assert_includes result["summary"], "production SYNTH:ALPHA FY2026/Q3 fixture gate is unchanged"
    assert_includes result["summary"], "vector=.0"
    assert_includes result["summary"], "without iterative scan recovered .44"
    assert_includes result["summary"], "strict_order iterative scanning recovered1.0"
    assert_includes result["summary"], "simulated foreground visibility"
    assert_includes result["summary"], "M9-08 precise rights/account/model/budgets"
    assert_includes result["sources"], "lib/research/acceptance.rb"
  end

  def test_m4_adapters_are_verified_without_claiming_paid_or_chat_access
    result = @knowledge.search("M4-02").first
    assert_equal "research-agent-adapters", result["id"]
    assert_equal "implemented", result["status"]
    assert_includes result["summary"], "not enabled paid access or a browser chatbot"
    assert_includes result["summary"], "not a new HTTP/SSE transport or asynchronous timeout wrapper"
    assert_includes result["summary"], "publication/knowability unknown"
    assert_includes result["sources"], "test/services/research_agent_adapters_test.rb"
  end

  def test_m4_native_loop_keeps_native_and_live_acceptance_separate
    %w[M4 M4-05 M4-06 M4-07].each do |query|
      result = @knowledge.search(query).first
      assert_equal "research-native-agent-loop", result["id"], query
      assert_equal "implemented", result["status"]
      assert_includes result["summary"], "zero external calls/spend"
      assert_includes result["summary"], "No-evidence/stale-only retained states avoid inference"
      assert_includes result["summary"], "not full claim entailment/financial correctness"
      assert_includes result["summary"], "Native M6-06 and M7-M9"
      assert_includes result["sources"], "test/services/research_agent_runtime_test.rb"
    end

  end

  def test_m5_durable_core_preserves_unknown_budget_and_no_paid_replay_gates
    %w[M5 M5-03 M5-04 M5-05 M5-07].each do |query|
      result = @knowledge.search(query).first
      assert_equal "research-durable-lifecycle", result["id"], query
      assert_equal "implemented", result["status"]
      assert_includes result["summary"], "no raw tool results"
      assert_includes result["summary"], "whole paid runs never auto-replay"
      assert_includes result["summary"], "source_budget_unknown"
      assert_includes result["summary"], "does not verify actual provider header"
      assert_includes result["summary"], "usage survives key rotation"
      assert_includes result["sources"], "app/models/research_source_usage.rb"
      assert_includes result["sources"], "test/services/research_agent_lifecycle_test.rb"
    end
  end

  def test_m0_permission_report_does_not_invent_scope_or_enable_egress
    ["M0-02", "M0-03"].each do |query|
      result = @knowledge.search(query).first
      assert_equal "m0-model-permission-readiness", result["id"]
      assert_equal "user_decision", result["status"]
      assert_includes result["summary"], "M0-02 remains partial"
      assert_includes result["summary"], "M0-03 is partial"
      assert_includes result["summary"], "user-reported Equibles permission granted"
      assert_includes result["summary"], "approval reference are unrecorded"
      assert_includes result["summary"], "real-source egress remains disabled"
      assert_includes result["summary"], "default abuse logs up to 30 days"
      assert_includes result["summary"], "1536 dimensions/cosine"
      assert_includes result["sources"], "https://equibles.com/legal/terms"
    end
  end

  def test_vector_restore_knowledge_preserves_existing_database_and_rollback_boundaries
    result = @knowledge.search("pgvector restore").first
    assert_equal "postgres-vector-foundation", result["id"]
    assert_equal "implemented", result["status"]
    assert_includes result["summary"], "unchanged digest-pinned PostgreSQL 16.15"
    assert_includes result["summary"], "scratch container is removed while backup is intentionally retained"
    assert_includes result["summary"], "no automatic DROP EXTENSION/CASCADE"
    assert_includes result["sources"], "bin/pgvector-rehearsal"
  end

  def test_vector_storage_is_implemented_without_claiming_inference_or_provider_access
    result = @knowledge.search("ResearchEmbeddingSpace").first
    assert_equal "research-vector-storage", result["id"]
    assert_equal "implemented", result["status"]
    assert_includes result["summary"], "Composite owner/checksum/chunker/preprocessing/current-revision foreign keys"
    assert_includes result["summary"], "current rights/revocation/retention"
    assert_includes result["summary"], "No permission grant, research controller, live egress or inference/chat runtime"
    assert_includes result["summary"], "New revisions are not implicitly indexed"
    assert_includes result["sources"], "db/migrate/20261107070000_add_research_ingestion.rb"
    assert_includes result["sources"], "test/models/research_storage_test.rb"
  end

  def test_ann_decision_is_bounded_to_the_measured_workload
    result = @knowledge.search("M1-07").first
    assert_equal "vector-index-decision", result["id"]
    assert_equal "implemented", result["status"]
    assert_includes result["summary"], "no persistent ANN index"
    assert_includes result["summary"], "independent Ruby cosine ground truth"
    assert_includes result["summary"], "not production benchmarks or M0/M9 end-to-end acceptance"
    assert_includes result["sources"], "bin/research-vector-benchmark"
  end

  def test_m2_implementation_distinguishes_offline_ingestion_from_live_permissions_and_rag
    result = @knowledge.search("M2-06").first
    assert_equal "research-ingestion", result["id"]
    assert_equal "implemented", result["status"]
    assert_includes result["summary"], "approved_owners defaults empty"
    assert_includes result["summary"], "No live provider or paid embedding request was executed"
    assert_includes result["summary"], "dispatched/uncertain batches remain blocked across request keys until review"
    assert_includes result["summary"], "incomplete/failed indexing cannot fall back to old text as current"
    assert_includes result["summary"], "M3 labels current uncertainty and denies unproved as-of history"
    assert_includes result["sources"], "test/services/research_ingestor_test.rb"
  end

  def test_retrieves_agent_direction_with_fixture_chat_and_native_gates
    result = @knowledge.search("conversational agent").first
    assert_equal "rails-native-research-agent", result["id"]
    assert_equal "user_decision", result["status"]
    assert_includes result["summary"], "do not enable paid/provider/private access"
    assert_includes result["summary"], "M4 installs pinned"
    assert_includes result["summary"], "internal events are not AG-UI compliance"
    assert_includes result["summary"], "shared Redis"
    assert_includes result["summary"], "Native M6-06 is partial"
    assert_includes result["sources"], "config/cable.yml"
  end

  def test_m6_chat_knowledge_distinguishes_verified_web_from_native_and_paid_gates
    %w[M6 M6-02 M6-03 M6-05 M6-06].each do |query|
      result = @knowledge.search(query).first
      assert_equal "research-authenticated-chat", result["id"], query
      assert_equal "implemented", result["status"]
      assert_includes result["summary"], "M6-06 explicitly partial"
      assert_includes result["summary"], "default0 including Compose"
      assert_includes result["summary"], "zero external requests/cost"
      assert_includes result["summary"], "Warden Rails session"
      assert_includes result["summary"], "blocks late snapshots"
      assert_includes result["summary"], "Snapshot polling cannot renew expired leases"
      assert_includes result["summary"], "Redis disconnect outage cannot prevent ordinary logout"
      assert_includes result["summary"], "Android lacks Java/SDK"
      assert_includes result["sources"], "app/channels/research_chat_channel.rb"
    end
  end

  def test_m7_workflow_record_distinguishes_quotation_support_from_financial_truth
    result = @knowledge.search("earnings-quotes-v1").find { |record| record["id"] == "research-grounded-workflow" }
    assert_equal "implemented", result["status"]
    assert_includes result["summary"], "not independent real-world truth"
    assert_includes result["summary"], "Invalid output fails before publication"
    assert_includes result["sources"], "test/services/research_earnings_workflow_test.rb"
  end

  def test_m8_disposal_record_keeps_backup_provider_and_billing_uncertainty_explicit
    result = @knowledge.search("RESEARCH_RESTORE_PENDING").first
    assert_equal "research-disposal", result["id"]
    assert_equal "implemented", result["status"]
    assert_includes result["summary"], "Accepted unknown usage stays uncertain"
    assert_includes result["summary"], "physical vacuum/WAL/snapshot/provider erasure remains unverified"
    assert_includes result["sources"], "test/services/research_disposal_test.rb"
  end

  def test_m3_retrieval_keeps_unknown_history_default_keyword_and_dispatch_gates_explicit
    result = @knowledge.search("M3-09").first
    assert_equal "research-temporal-retrieval", result["id"]
    assert_equal "implemented", result["status"]
    assert_includes result["summary"], "Keyword English generated tsvector/GIN/websearch/ts_rank_cd is the default"
    assert_includes result["summary"], "Unknown or tied restatement timelines conservatively block"
    assert_includes result["summary"], "transmitted data cannot be recalled"
    assert_includes result["summary"], "No live/paid requests"
    assert_includes result["sources"], "test/services/research_retriever_test.rb"
  end

  def test_retrieves_equibles_contract_review_without_claiming_complete_account_verification
    %w[C01 C02].each do |query|
      result = @knowledge.search(query).first
      assert_equal "equibles-price-contract-review", result["id"]
      assert_equal "verified_fact", result["status"]
      assert_includes result["summary"], "C01 remains partial"
      assert_includes result["summary"], "C02 contract/sample verification is complete"
      assert_includes result["sources"], "https://api.equibles.com/openapi/v1.json"
    end
  end

  def test_retrieves_equibles_rights_without_treating_api_access_as_permission
    result = @knowledge.search("C03").first
    assert_equal "equibles-restricted-data-rights", result["id"]
    assert_includes result["summary"], "explicitly exclude"
    assert_includes result["summary"], "C03 remains blocked"
    assert_includes result["summary"], "Owner approvals remain empty"
    assert_includes result["sources"], "https://equibles.com/legal/terms"
  end

  def test_retrieves_current_user_decisions
    result = @knowledge.search("Kraken connection modes").first
    assert_equal "kraken-connection-modes", result["id"]
    assert_equal "user_decision", result["status"]
  end

  def test_retrieves_copilot_maintenance_and_local_only_boundaries
    result = @knowledge.search("retrieval").first
    assert_equal "project-retrieval-workflow", result["id"]
    assert_includes result["summary"], "plan.md and todo.md are ignored local files"
    assert_includes result["sources"], ".github/copilot-instructions.md"
  end

  def test_commit_query_retrieves_same_commit_maintenance_policy
    result = @knowledge.search("commit").first
    assert_equal "project-retrieval-workflow", result["id"]
    assert_includes result["summary"], "before every authorized commit"
    assert_includes result["summary"], "in that same commit"
  end

  def test_session_queries_retrieve_context_reuse_and_freshness_policy
    ["new session", "session context", "redundant retrieval"].each do |query|
      result = @knowledge.search(query).first
      assert_equal "project-retrieval-workflow", result["id"], query
      assert_includes result["summary"], "reuse relevant session evidence"
      assert_includes result["summary"], "do not assume memory parity"
      assert_includes result["summary"], "sources, and freshness"
    end
  end

  def test_container_query_retrieves_isolation_and_queue_durability_limits
    result = @knowledge.search("Docker Sidekiq Redis").first
    assert_equal "local-compose-runtime", result["id"]
    assert_equal "implemented", result["status"]
    assert_includes result["sources"], "compose.yml"
    assert_includes result["summary"], "noeviction"
    assert_includes result["summary"], "not exactly-once"
  end

  def test_retention_query_preserves_storage_and_scheduling_boundaries
    result = @knowledge.search("Equibles retention cleanup").first
    assert_equal "equibles-private-evidence", result["id"]
    assert_includes result["summary"], "snapshots are not Rails-encrypted attributes"
    assert_includes result["summary"], "not a wall-clock deletion guarantee"
    assert_includes result["sources"], "app/jobs/expire_equibles_evidence_job.rb"
  end

  def test_sandbox_query_preserves_synthetic_and_real_execution_boundaries
    result = @knowledge.search("synthetic sandbox").first
    assert_equal "synthetic-execution-sandbox", result["id"]
    assert_includes result["summary"], "not licensed backtests"
    assert_includes result["summary"], "Account deletion is explicitly blocked"
    assert_includes result["sources"], "db/structure.sql"
  end

  def test_research_query_does_not_invent_alvis_or_model_authority
    result = @knowledge.search("research policy lab").first
    assert_equal "synthetic-research-policy", result["id"]
    assert_includes result["summary"], "not ALVIS or model inference"
    assert_includes result["summary"], "No uploads"
  end

  def test_deposit_query_preserves_non_actionable_review_status
    result = @knowledge.search("deposit information").first
    assert_equal "deposit-information-boundary", result["id"]
    assert_includes result["summary"], "cannot activate an adapter"
    assert_includes result["summary"], "every destination is non-actionable"
  end

  def test_returns_bounded_results_with_sources_and_deterministic_order
    results = @knowledge.search("Equibles Kraken", limit: 2)
    assert_equal 2, results.length
    assert_equal results, @knowledge.search("Equibles Kraken", limit: 2)
    assert results.all? { |record| !record["sources"].empty? }
    refute results.any? { |record| record.key?("aliases") }
  end

  def test_unknown_queries_have_no_matches
    assert_empty @knowledge.search("unmatchedxyz")
  end

  def test_rejects_empty_queries_and_invalid_limits
    [nil, "", "   ", "what is the", "!!!"].each do |query|
      assert_raises(ArgumentError) { @knowledge.search(query) }
    end
    [0, -1, 11, "2", nil].each do |limit|
      assert_raises(ArgumentError) { @knowledge.search("ALVIS", limit: limit) }
    end
  end

  def test_rejects_invalid_record_shapes
    [{}, [nil], [{}]].each do |records|
      with_store(records) do |path|
        assert_raises(ArgumentError) { ProjectKnowledge.new(path: path) }
      end
    end
  end

  def test_rejects_duplicates_missing_sources_invalid_dates_and_status
    record = JSON.parse(File.read(ProjectKnowledge::DEFAULT_PATH)).first
    [[record, record],
     [record.merge("sources" => [])],
     [record.merge("updated_on" => "2026-02-30")],
     [record.merge("status" => "assumed")],
     [record.merge("aliases" => [nil])]].each do |records|
      with_store(records) do |path|
        assert_raises(ArgumentError) { ProjectKnowledge.new(path: path) }
      end
    end
  end

  def test_cli_returns_structured_matches_without_rails
    output, error, status = run_cli("Elvis AI")
    assert status.success?, error
    assert_equal "", error
    assert_equal "equibles-alvis", JSON.parse(output)["matches"].first["id"]
  end

  def test_cli_reports_invalid_input_and_unknown_queries_explicitly
    output, error, status = run_cli
    refute status.success?
    assert_equal "", output
    assert_includes error, "Usage:"

    output, error, status = run_cli("unmatchedxyz")
    assert status.success?, error
    assert_empty JSON.parse(output)["matches"]
  end

  private

  def with_store(records)
    Tempfile.create(["project-knowledge", ".json"]) do |file|
      file.write(JSON.generate(records))
      file.flush
      yield file.path
    end
  end

  def run_cli(*arguments)
    command = -> { Open3.capture3(RbConfig.ruby, File.expand_path("../../bin/project-knowledge", __dir__), *arguments) }
    defined?(Bundler) ? Bundler.with_unbundled_env(&command) : command.call
  end
end
