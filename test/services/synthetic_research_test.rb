require "test_helper"

class SyntheticResearchTest < ActiveSupport::TestCase
  test "only the valid fixture passes all deterministic policy gates" do
    SyntheticResearch::SCENARIOS.each_key do |scenario|
      insight, evidence, budget = SyntheticResearch.fixture(scenario)
      result = SyntheticResearch.evaluate(insight, evidence: evidence, now: SyntheticResearch::CLOCK,
                                          budget_remaining: budget)
      assert_equal scenario == "valid", result.accepted, scenario
      assert result.reason.present?
    end
  end

  test "malformed and adversarial candidates cannot confer tools or sizing authority" do
    insight, evidence, = SyntheticResearch.fixture("valid")
    [nil, [], "instructions", insight.merge(unknown: "field"), insight.merge("quantity" => "NaN"),
     insight.merge("endpoint" => "https://example.invalid/order"),
     insight.merge("policy_version" => "other"),
     insight.merge("evidence_ids" => ["fixture-quote-1", "fixture-quote-1"]),
     insight.merge("expires_at" => "not-a-time"),
     insight.merge("expires_at" => (SyntheticResearch::CLOCK + 301).iso8601)].each do |candidate|
      refute SyntheticResearch.evaluate(candidate, evidence: evidence, now: SyntheticResearch::CLOCK,
                                        budget_remaining: 1).accepted
    end
    [nil, 0, -1, "1"].each do |budget|
      refute SyntheticResearch.evaluate(insight, evidence: evidence, now: SyntheticResearch::CLOCK,
                                        budget_remaining: budget).accepted
    end
  end

  test "citations must match source instrument and the exact freshness boundary" do
    insight, evidence, = SyntheticResearch.fixture("valid")
    row = evidence.fetch("fixture-quote-1")
    [{ "source" => "real_provider" }, { "instrument_id" => "DEMO-B" },
     { "observed_at" => (SyntheticResearch::CLOCK + 1).iso8601 },
     { "observed_at" => (SyntheticResearch::CLOCK - 120).iso8601 }].each do |changes|
      refute SyntheticResearch.evaluate(insight, evidence: { "fixture-quote-1" => row.merge(changes) },
                                        now: SyntheticResearch::CLOCK, budget_remaining: 1).accepted
    end
  end
end
