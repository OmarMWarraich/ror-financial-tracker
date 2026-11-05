require_relative "../sandbox_test_support"

class SandboxLedgerTest < Minitest::Test
  include SandboxTestSupport
  include ActiveSupport::Testing::TimeHelpers

  def test_fixed_sizing_fees_slippage_and_synchronous_reservations
    mandate = activate
    order = execute(mandate)
    assert_equal "buy", order.side
    assert_equal 2, order.quantity
    assert_equal BigDecimal("100.10"), order.price
    assert_equal BigDecimal("0.21"), order.fee
    assert_equal BigDecimal("200.41"), order.reserved_cash
    assert_equal 0, order.reserved_quantity
    assert_equal "filled", order.state
    assert_equal BigDecimal("799.59"), @account.reload.cash
    assert_equal 2, @account.quantity
    assert_equal BigDecimal("200.41"), @account.cost_basis
    assert_equal %w[reserved synthetic_filled], @account.sandbox_events.last(2).map(&:kind)

    @ledger.load_fixture!(account_id: @account.id, fixture_key: "fall-v1")
    sale = execute(mandate)
    assert_equal "sell", sale.side
    assert_equal 2, sale.reserved_quantity
    assert_equal BigDecimal("99.90"), sale.price
    assert_equal BigDecimal("0.20"), sale.fee
    assert_equal BigDecimal("999.19"), @account.reload.cash
    assert_equal 0, @account.quantity
    assert_equal 0, @account.cost_basis
    assert_raises(SandboxLedger::Denied) { execute(mandate) }
  end

  def test_idempotent_retry_never_creates_another_fill_even_after_revocation
    mandate = activate
    key = SecureRandom.uuid
    first = execute(mandate, key)
    balance = @account.reload.cash
    @ledger.load_fixture!(account_id: @account.id, fixture_key: "fall-v1")
    @ledger.transition!(account_id: @account.id, mandate_id: mandate.id, to: "revoked")
    assert_equal first.id, execute(mandate, key).id
    assert_equal 1, @account.sandbox_orders.count
    assert_equal balance, @account.reload.cash
    assert_raises(SandboxLedger::Denied) { execute(mandate, nil) }
    assert_raises(SandboxLedger::Denied) { execute(mandate, "model-order") }
    assert_raises(SandboxLedger::Denied) { execute(draft, key) }
  end

  def test_ownership_account_swap_and_unsupported_environment_fail_closed
    mandate = activate
    assert_raises(ActiveRecord::RecordNotFound) do
      SandboxLedger.new(@other).execute!(account_id: @account.id, mandate_id: mandate.id, request_key: SecureRandom.uuid)
    end
    other_account = SandboxLedger.new(@other).create_account!(initial_cash: 1000)
    assert_raises(ActiveRecord::RecordNotFound) do
      @ledger.execute!(account_id: other_account.id, mandate_id: mandate.id, request_key: SecureRandom.uuid)
    end
    assert_raises(ActiveRecord::RecordNotFound) do
      SandboxLedger.new(@other).transition!(account_id: @account.id, mandate_id: mandate.id, to: "active", password: PASSWORD)
    end
    SandboxMandate.where(id: mandate.id).update_all(environment: "paper")
    assert_raises(SandboxLedger::Denied) { execute(mandate) }
  end

  def test_activation_step_up_failures_are_durable_and_limits_require_renewed_consent
    mandate = draft
    5.times do
      assert_raises(SandboxLedger::Denied) do
        @ledger.transition!(account_id: @account.id, mandate_id: mandate.id, to: "active", password: "wrong")
      end
    end
    assert_equal 5, @owner.reload.sensitive_action_failures
    assert @owner.sensitive_action_locked_until > Time.current
    assert_equal "draft", mandate.reload.state
    assert_raises(SandboxLedger::Denied) { activate(mandate) }
    assert_empty @account.sandbox_orders
  end

  def test_pause_resume_revoke_and_expiry
    mandate = draft
    assert_raises(SandboxLedger::Denied) { execute(mandate) }
    activate(mandate)
    @ledger.transition!(account_id: @account.id, mandate_id: mandate.id, to: "paused")
    assert_raises(SandboxLedger::Denied) { execute(mandate) }
    activate(mandate)
    travel_to(2.hours.from_now) do
      assert_raises(SandboxLedger::Denied) { execute(mandate) }
      assert_raises(SandboxLedger::Denied) { activate(mandate) }
    end
    @ledger.transition!(account_id: @account.id, mandate_id: mandate.id, to: "revoked")
    assert_raises(SandboxLedger::Denied) { activate(mandate) }
    assert_empty @account.sandbox_orders
  end

  def test_fixtures_are_allowlisted_stale_missing_future_and_hold_block
    mandate = activate
    assert_raises(SandboxLedger::Denied) { @ledger.load_fixture!(account_id: @account.id, fixture_key: "BTCUSD") }
    travel_to(16.minutes.from_now) { assert_raises(SandboxLedger::Denied) { execute(mandate) } }
    @account.update_columns(fixture_key: "missing-v1")
    assert_raises(SandboxLedger::Denied) { execute(mandate) }
    @account.update_columns(fixture_key: "rise-v1", fixture_loaded_at: 1.minute.from_now)
    assert_raises(SandboxLedger::Denied) { execute(mandate) }
    @ledger.load_fixture!(account_id: @account.id, fixture_key: "flat-v1")
    assert_raises(SandboxLedger::Denied) { execute(mandate) }
    assert_empty @account.sandbox_orders
  end

  def test_capital_notional_quantity_exposure_loss_and_no_overdraft
    mandate = activate(draft(capital_limit: 250, max_notional: 150, max_quantity: 100, max_exposure: 200))
    assert_equal 1, execute(mandate).quantity
    assert_equal 1, execute(mandate).quantity
    assert_raises(SandboxLedger::Denied) { execute(mandate) }
    assert_equal 2, @account.reload.quantity
    assert @account.cost_basis <= mandate.capital_limit
    assert @account.cash >= 0
    @ledger.transition!(account_id: @account.id, mandate_id: mandate.id, to: "paused")
    limited = activate(draft(loss_limit: "0.01"))
    assert_raises(SandboxLedger::Denied) { execute(limited) }
    @ledger.load_fixture!(account_id: @account.id, fixture_key: "fall-v1")
    assert_equal "sell", execute(limited).side
  end

  def test_only_one_active_mandate_and_terms_reject_arbitrary_inputs
    activate
    assert_raises(SandboxLedger::Denied) { activate(draft) }
    assert_raises(SandboxLedger::Denied) { draft(code: "system('network')") }
    assert_raises(SandboxLedger::Denied) { draft(model_output: "BUY") }
    assert_raises(SandboxLedger::Denied) { draft(provider_quote: 100) }
  end

  def test_failed_fill_is_atomic_including_reservation_and_audit
    mandate = activate
    count = @account.sandbox_events.count
    balance = @account.cash
    original = @ledger.method(:event!)
    failing_event = lambda do |account, kind, details|
      raise "simulated database failure" if kind == "synthetic_filled"
      original.call(account, kind, details)
    end
    @ledger.stub(:event!, failing_event) do
      assert_raises(RuntimeError) { execute(mandate) }
    end
    assert_equal balance, @account.reload.cash
    assert_equal 0, @account.quantity
    assert_equal count, @account.sandbox_events.count
    assert_empty @account.sandbox_orders
  end
end
