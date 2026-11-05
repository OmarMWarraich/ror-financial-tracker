require "minitest/autorun"
require "active_support/all"
require "digest"
require_relative "../../app/services/sandbox_ledger"
require_relative "../../app/services/sandbox_fixtures"

class SandboxFixturesTest < Minitest::Test
  Account = Struct.new(:fixture_key, :fixture_loaded_at)

  def test_explicit_reproducible_fictional_provenance
    now = Time.current
    account = Account.new("rise-v1", now)
    first = SandboxFixtures.fetch!(account, now: now)
    second = SandboxFixtures.fetch!(account, now: now + 60)
    assert_equal first, second
    assert_equal BigDecimal("100"), first[:price]
    assert_equal 64, first[:digest].size
    assert_includes SandboxFixtures::PROVENANCE, "fictional"
    assert SandboxFixtures::DATA.frozen?
    assert SandboxFixtures::DATA.values.all?(&:frozen?)
  end

  def test_missing_stale_and_future_observations_fail_closed
    now = Time.current
    [Account.new("missing", now), Account.new(nil, now), Account.new("rise-v1", nil),
     Account.new("rise-v1", now - 901), Account.new("rise-v1", now + 1)].each do |account|
      assert_raises(SandboxLedger::Denied) { SandboxFixtures.fetch!(account, now: now) }
    end
  end
end
