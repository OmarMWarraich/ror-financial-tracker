require_relative "../sandbox_test_support"

class SandboxRecordsTest < Minitest::Test
  include SandboxTestSupport

  def test_all_limits_are_required_positive_bounded_and_fixed
    SandboxMandate::BOUNDS.each do |field|
      [nil, 0, -1].each do |value|
        assert_raises(ActiveRecord::RecordInvalid, "#{field}=#{value.inspect}") { draft(field => value) }
      end
    end
    assert_raises(ActiveRecord::RecordInvalid) { draft(max_quantity: 101) }
    assert_raises(ActiveRecord::RecordInvalid) { draft(max_notional: 901) }
    assert_raises(ActiveRecord::RecordInvalid) { draft(max_exposure: 901) }
    assert_raises(ActiveRecord::RecordInvalid) { draft(loss_limit: 901) }
    assert_raises(ActiveRecord::RecordInvalid) { draft(capital_limit: 10_001) }
    assert_raises(ActiveRecord::RecordInvalid) { draft(expires_at: 2.days.from_now) }
    assert_raises(ActiveRecord::RecordInvalid) { draft(expires_at: 1.second.ago) }
    assert_raises(SandboxLedger::Denied) { draft(rule_version: "arbitrary Ruby") }
  end

  def test_mandate_terms_and_account_identity_are_immutable
    mandate = activate
    assert_raises(ActiveRecord::ReadonlyAttributeError) { mandate.update!(max_quantity: 99) }
    assert_raises(ActiveRecord::ReadonlyAttributeError) { @account.update!(user: @other) }
    assert_raises(ActiveRecord::ReadonlyAttributeError) { @account.update!(environment: "live") }
    assert_equal 2, mandate.reload.max_quantity
  end

  def test_ledger_events_and_fills_are_append_only_in_orm_and_database
    order = execute(activate)
    event = @account.sandbox_events.last
    assert_raises(ActiveRecord::ReadOnlyRecord) { event.update!(kind: "changed") }
    assert_raises(ActiveRecord::ReadOnlyRecord) { order.destroy! }
    [SandboxEvent.where(id: event.id), SandboxOrder.where(id: order.id)].each do |scope|
      error = assert_raises(ActiveRecord::StatementInvalid) do
        ActiveRecord::Base.transaction(requires_new: true) { scope.delete_all }
      end
      assert_includes error.message, "append-only"
    end
    assert_equal "filled", order.reload.state
  end

  def test_account_is_independent_and_cannot_be_funded_above_hard_cap
    assert_equal "synthetic", @account.environment
    assert_equal "USD", @account.currency
    assert_equal 0, @account.quantity
    other_ledger = SandboxLedger.new(@other)
    assert_raises(ActiveRecord::RecordInvalid) { other_ledger.create_account!(initial_cash: 10_001) }
    assert_raises(ActiveRecord::RecordInvalid) { other_ledger.create_account!(initial_cash: 0) }
  end
end
