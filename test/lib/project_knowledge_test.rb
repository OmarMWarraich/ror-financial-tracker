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

  def test_retrieves_current_user_decisions
    result = @knowledge.search("Kraken connection modes").first
    assert_equal "kraken-connection-modes", result["id"]
    assert_equal "user_decision", result["status"]
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
