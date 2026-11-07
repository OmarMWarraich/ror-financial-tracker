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

  def test_retrieves_native_agent_direction_without_claiming_implemented_chat
    result = @knowledge.search("conversational agent").first
    assert_equal "rails-native-research-agent", result["id"]
    assert_equal "user_decision", result["status"]
    assert_includes result["summary"], "not implemented model/MCP/chat access"
    assert_includes result["summary"], "AG-UI is optional"
    assert_includes result["summary"], "cross-process worker broadcasts"
    assert_includes result["sources"], "config/cable.yml"
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
