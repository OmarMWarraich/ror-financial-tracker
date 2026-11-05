class SandboxLedger
  class Denied < StandardError; end

  def initialize(owner)
    @owner = owner
  end

  def create_account!(initial_cash:)
    @owner.with_lock do
      account = SandboxAccount.create!(user: @owner, initial_cash: initial_cash, cash: initial_cash,
                                       fixture_key: "rise-v1", fixture_loaded_at: Time.current)
      event!(account, "account_created", currency: "USD", initial_cash: account.initial_cash.to_s, environment: "synthetic")
      account
    end
  end

  def draft!(account_id:, terms:)
    locked(account_id) do |account|
      attributes = terms.to_h.symbolize_keys
      raise Denied, "Unsupported mandate fields." unless (attributes.keys - SandboxMandate::BOUNDS - [:expires_at]).empty?
      mandate = account.sandbox_mandates.create!(attributes)
      event!(account, "mandate_drafted", mandate_id: mandate.id, terms: mandate.attributes.slice(*SandboxMandate::TERMS.map(&:to_s)))
      mandate
    end
  end

  def transition!(account_id:, mandate_id:, to:, password: nil)
    if to == "active"
      SandboxAccount.where(user_id: @owner.id).find(account_id).sandbox_mandates.find(mandate_id)
      # Step-up failures must commit independently of a denied ledger transaction.
      raise Denied, "Confirm your current application password." unless SensitiveActionAuthentication.verify(@owner, password)
    end
    locked(account_id) do |account|
      mandate = account.sandbox_mandates.find(mandate_id)
      allowed = { "draft" => %w[active revoked], "active" => %w[paused revoked], "paused" => %w[active revoked], "revoked" => [] }
      raise Denied, "Invalid mandate transition." unless allowed.fetch(mandate.state).include?(to)
      if to == "active"
        raise Denied, "Mandate expired; create and approve a new draft." if mandate.expired?
        raise Denied, "Pause or revoke the existing active mandate." if account.sandbox_mandates.where(state: "active").where.not(id: mandate.id).exists?
        SandboxFixtures.fetch!(account)
        mandate.approved_at = Time.current
      end
      mandate.update!(state: to)
      event!(account, "mandate_#{to}", mandate_id: mandate.id)
      mandate
    end
  end

  def load_fixture!(account_id:, fixture_key:)
    raise Denied, "Only built-in fictional fixtures are allowed." unless SandboxFixtures::DATA.key?(fixture_key)
    locked(account_id) do |account|
      account.update!(fixture_key: fixture_key, fixture_loaded_at: Time.current)
      event!(account, "fixture_loaded", fixture_key: fixture_key, provenance: SandboxFixtures::PROVENANCE)
    end
  end

  def execute!(account_id:, mandate_id:, request_key:)
    raise Denied, "A UUID request identity is required." unless request_key.is_a?(String) && request_key.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
    locked(account_id) do |account|
      mandate = account.sandbox_mandates.find(mandate_id)
      previous = SandboxOrder.find_by(user_id: @owner.id, request_key: request_key)
      if previous
        unless previous.sandbox_account_id == account.id && previous.sandbox_mandate_id == mandate.id
          raise Denied, "Request identity is already bound to another account or mandate."
        end
        next previous
      end
      validate_authority!(account, mandate)
      fixture = SandboxFixtures.fetch!(account)
      side = SandboxStrategy.decide!(version: mandate.rule_version, fixture: fixture)
      raise Denied, "Rule chose hold; no synthetic order." if side == :hold
      fill!(account, mandate, fixture, side, request_key)
    end
  rescue ActiveRecord::RecordNotUnique
    raise Denied, "Request identity conflict; reload the ledger."
  end

  private

  def locked(account_id)
    account = SandboxAccount.where(user_id: @owner.id).find(account_id)
    account.with_lock { yield account }
  end

  def event!(account, kind, details)
    account.sandbox_events.create!(kind: kind, details: details)
  end

  def validate_authority!(account, mandate)
    unless account.environment == "synthetic" && account.currency == "USD" &&
           mandate.environment == "synthetic" && mandate.instrument == SandboxFixtures::INSTRUMENT &&
           mandate.session == "fixture" && mandate.order_type == "synthetic_market" &&
           mandate.state == "active" && mandate.approved_at && !mandate.expired? && mandate.valid?
      raise Denied, "Synthetic authority is inactive, expired, or invalid."
    end
  end

  def fill!(account, mandate, fixture, side, request_key)
    mid = fixture.fetch(:price)
    price = (mid * (side == :buy ? BigDecimal("1.001") : BigDecimal("0.999"))).round(2)
    quantity = [mandate.max_quantity, (mandate.max_notional / price).floor].min
    quantity = [quantity, account.quantity].min if side == :sell
    if side == :buy
      # Reduce sizing to available cash, fee-inclusive capital, and marked exposure.
      quantity = [quantity, (account.cash / (price * BigDecimal("1.001"))).floor,
                  ((mandate.capital_limit - account.cost_basis) / (price * BigDecimal("1.001"))).floor,
                  (mandate.max_exposure / mid).floor - account.quantity].min
    end
    raise Denied, "No quantity fits funds, holdings, capital, notional, and exposure limits." unless quantity.positive?
    notional = price * quantity
    fee = (notional * BigDecimal("0.001")).ceil(2)
    debit = notional + fee
    new_cash = account.cash + (side == :buy ? -debit : notional - fee)
    new_quantity = account.quantity + (side == :buy ? quantity : -quantity)
    new_basis = if side == :buy
      account.cost_basis + debit
    else
      new_quantity.zero? ? 0.to_d : (account.cost_basis * new_quantity / account.quantity).round(2)
    end
    if new_cash.negative? || new_quantity.negative? || notional > mandate.max_notional ||
       (side == :buy && (new_basis > mandate.capital_limit || new_quantity * mid > mandate.max_exposure ||
                         account.initial_cash - (new_cash + new_quantity * mid) >= mandate.loss_limit))
      raise Denied, "Projected synthetic fill breaches a mandate limit."
    end
    reserved_cash = side == :buy ? debit : 0
    reserved_quantity = side == :sell ? quantity : 0
    event!(account, "reserved", request_key: request_key, cash: reserved_cash.to_s, quantity: reserved_quantity)
    order = account.sandbox_orders.create!(
      sandbox_mandate: mandate, user: @owner, request_key: request_key,
      fixture_key: fixture.fetch(:key), fixture_digest: fixture.fetch(:digest),
      side: side.to_s, state: "filled", quantity: quantity, price: price, fee: fee,
      reserved_cash: reserved_cash, reserved_quantity: reserved_quantity
    )
    account.update!(cash: new_cash, quantity: new_quantity, cost_basis: new_basis)
    event!(account, "synthetic_filled", order_id: order.id, request_key: request_key,
           fixture_key: fixture.fetch(:key), fixture_digest: fixture.fetch(:digest),
           cash: new_cash.to_s, quantity: new_quantity, rule_version: mandate.rule_version)
    order
  end
end
