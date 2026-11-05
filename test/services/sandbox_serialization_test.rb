require_relative "../sandbox_test_support"

class SandboxSerializationTest < Minitest::Test
  include SandboxTestSupport

  # Dedicated test schema keeps committed concurrency fixtures out of other suites.
  # LIKE copies the production uniqueness/check constraints used by these races.
  def setup
    @schema = "sandbox_test_#{SecureRandom.hex(8)}"
    @original_path = ActiveRecord::Base.connection.schema_search_path
    connection = ActiveRecord::Base.connection
    connection.execute("CREATE SCHEMA #{@schema}")
    %w[users sandbox_accounts sandbox_mandates sandbox_orders sandbox_events].each do |table|
      connection.execute("CREATE TABLE #{@schema}.#{table} (LIKE #{table} INCLUDING ALL)")
    end
    connection.schema_search_path = "#{@schema}, public"
    @owner = User.create!(email: "concurrency-#{SecureRandom.hex(8)}@example.test", password: PASSWORD)
    @ledger = SandboxLedger.new(@owner)
    @account = @ledger.create_account!(initial_cash: 1000)
  end

  def teardown
    ActiveRecord::Base.connection.schema_search_path = @original_path
    ActiveRecord::Base.connection.execute("DROP SCHEMA #{@schema} CASCADE")
  end

  def test_concurrent_distinct_requests_cannot_overreserve_cash_or_exposure
    mandate = activate(draft(max_exposure: 200))
    results = race(2) { |ledger, _| ledger.execute!(account_id: @account.id, mandate_id: mandate.id, request_key: SecureRandom.uuid) }
    assert_equal 1, results.count { |value| value.is_a?(SandboxOrder) }
    assert_equal 1, results.count { |value| value.is_a?(SandboxLedger::Denied) }
    assert_equal 1, @account.sandbox_orders.count
    assert_equal 2, @account.reload.quantity
    assert_equal BigDecimal("799.59"), @account.cash
  end

  def test_concurrent_duplicate_requests_return_one_original_fill
    mandate = activate
    key = SecureRandom.uuid
    results = race(2) { |ledger, _| ledger.execute!(account_id: @account.id, mandate_id: mandate.id, request_key: key) }
    assert results.all? { |value| value.is_a?(SandboxOrder) }, results.inspect
    assert_equal 1, results.map(&:id).uniq.size
    assert_equal 1, @account.sandbox_orders.count
    assert_equal 2, @account.reload.quantity
  end

  def test_revocation_serializes_a_waiting_execution
    mandate = activate
    started = Queue.new
    result = Queue.new
    worker = nil
    @account.with_lock do
      worker = in_schema_thread do |ledger|
        started << true
        begin
          result << ledger.execute!(account_id: @account.id, mandate_id: mandate.id, request_key: SecureRandom.uuid)
        rescue SandboxLedger::Denied => error
          result << error
        end
      end
      started.pop
      @ledger.transition!(account_id: @account.id, mandate_id: mandate.id, to: "revoked")
    end
    worker.value
    assert_kind_of SandboxLedger::Denied, result.pop
    assert_empty @account.sandbox_orders
  end

  private

  def race(count)
    ready = Queue.new
    start = Queue.new
    workers = count.times.map do |index|
      in_schema_thread do |ledger|
        ready << true
        start.pop
        begin
          yield ledger, index
        rescue SandboxLedger::Denied => error
          error
        end
      end
    end
    count.times { ready.pop }
    count.times { start << true }
    workers.map(&:value)
  end

  def in_schema_thread
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        old_path = connection.schema_search_path
        begin
          connection.schema_search_path = "#{@schema}, public"
          yield SandboxLedger.new(User.find(@owner.id))
        ensure
          connection.schema_search_path = old_path
        end
      end
    end
  end
end
