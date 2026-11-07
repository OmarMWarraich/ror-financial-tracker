require "test_helper"
require Rails.root.join("lib/research/acceptance")

class ResearchAcceptanceTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "evaluation rejects an open transaction without creating corpus" do
    owners = User.count
    ApplicationRecord.transaction do
      error = assert_raises(Research::Error) { Research::Acceptance.new.call }
      assert_equal "acceptance_requires_isolated_test_database", error.code
    end
    assert_equal owners, User.count
  end

  test "disabling both retrieval channels fails rather than returning empty evidence" do
    error = assert_raises(Research::Error) {
      Research::HybridRanker.new(rows: nil, space: nil, query: "Original query", vector: nil, recency: false, keyword: false)
    }
    assert_equal "invalid_retrieval_channel", error.code
  end

  test "fixed original corpus reports separate retrieval support temporal and ANN measurements without provider work" do
    owners = User.count
    report = Net::HTTP.stub(:start, ->(*) { flunk "Evaluation must not call providers" }) { Research::Acceptance.new.call }
    assert_equal "original-earnings-acceptance-v1", report[:version]
    assert_equal "45a287e768c35d8a02fbb7cc53337e67a7309ba6d0dc03b76a027f8c8ab3b652", report[:corpus_sha256]
    assert_equal [24, 120, 40], report.values_at(:documents, :passages, :questions)
    assert_equal({ companies: 4, fiscal_periods: 3, source_kinds: 2, owners: 2 }, report[:corpus_groups])
    assert_equal({ supported: 20, missing_conflicting_scope: 10, temporal_adversarial: 10 }, report[:question_groups])
    assert_equal 0, report[:external_requests]
    assert_equal 0, report[:cost_nanos]
    assert_equal "not_approved", report[:hybrid_adoption]
    assert_operator report[:baselines]["keyword"]["recall_at_5"], :>=, 0.9
    report[:baselines].each_value do |metrics|
      assert_equal 0, metrics["ownership_temporal_scope_leaks"]
      assert_equal 0, metrics["negative_false_evidence"]
      assert_equal metrics["validated_claims"], metrics["unsupported_number_probes_rejected"]
      assert metrics["extractive_fixture_claim_support"].nil? || metrics["extractive_fixture_claim_support"] >= 0.95
      assert_operator metrics["p95_ms"], :>, 0
    end
    assert_equal 0, report[:filtered_ann_candidates]["ownership_temporal_scope_leaks"]
    assert_operator report[:filtered_ann_candidates]["iterative_recall_at_5_against_exact_candidates"], :>=, 0.9
    assert_equal 20, report[:fixture_workflow][:runs]
    assert_operator report[:fixture_workflow][:p95_ms], :<=, 2000
    assert_operator report[:fixture_workflow][:cold_ms], :>, 0
    assert_operator report[:fixture_workflow][:warm_p95_ms], :<=, 2000
    assert_equal owners, User.count
    assert_not ApplicationRecord.connection.select_value("SELECT EXISTS(SELECT 1 FROM pg_indexes WHERE indexname LIKE 'original_acceptance_%')")
  end
end
