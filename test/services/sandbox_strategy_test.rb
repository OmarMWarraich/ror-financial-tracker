require "minitest/autorun"
require "bigdecimal"
require_relative "../../app/services/sandbox_ledger"
require_relative "../../app/services/sandbox_strategy"

class SandboxStrategyTest < Minitest::Test
  def test_fixed_versioned_declarative_rule
    assert_equal :buy, decide(100, 99)
    assert_equal :sell, decide(100, 101)
    assert_equal :hold, decide(100, 100)
    assert_equal "SYNTH-ALPHA", SandboxStrategy::RULE[:instrument]
    assert SandboxStrategy::RULE.frozen?
  end

  def test_no_dynamic_execution_interface
    assert_raises(ArgumentError) do
      SandboxStrategy.decide!(version: "trend-v1", fixture: {}, model: "buy")
    end
    refute_respond_to SandboxStrategy, :eval
    assert_raises(SandboxLedger::Denied) do
      SandboxStrategy.decide!(version: "uploaded-code", fixture: {})
    end
  end

  private

  def decide(price, prior)
    SandboxStrategy.decide!(version: "trend-v1", fixture: { price: BigDecimal(price.to_s), prior: BigDecimal(prior.to_s) })
  end
end
