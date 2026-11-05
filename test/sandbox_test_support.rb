ENV["RAILS_ENV"] ||= "test"
abort "Sandbox tests require RAILS_ENV=test" unless ENV["RAILS_ENV"] == "test"
require_relative "../config/environment"
require "minitest/autorun"
require "minitest/mock"
require "active_support/testing/time_helpers"

module SandboxTestSupport
  PASSWORD = "synthetic-test-password".freeze

  def setup
    super
    ActiveRecord::Base.connection.begin_transaction(joinable: false)
    @owner = User.create!(email: "sandbox-#{SecureRandom.hex(8)}@example.test", password: PASSWORD)
    @other = User.create!(email: "sandbox-other-#{SecureRandom.hex(8)}@example.test", password: PASSWORD)
    @ledger = SandboxLedger.new(@owner)
    @account = @ledger.create_account!(initial_cash: 1000)
  end

  def teardown
    ActiveRecord::Base.connection.rollback_transaction
    super
  end

  def terms(overrides = {})
    { capital_limit: 900, max_notional: 300, max_quantity: 2, max_exposure: 800,
      loss_limit: 100, expires_at: 1.hour.from_now }.merge(overrides)
  end

  def draft(overrides = {})
    @ledger.draft!(account_id: @account.id, terms: terms(overrides))
  end

  def activate(mandate = draft)
    @ledger.transition!(account_id: @account.id, mandate_id: mandate.id, to: "active", password: PASSWORD)
  end

  def execute(mandate, key = SecureRandom.uuid)
    @ledger.execute!(account_id: @account.id, mandate_id: mandate.id, request_key: key)
  end
end
