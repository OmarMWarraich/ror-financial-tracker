require "test_helper"
require "minitest/mock"

class EquiblesEvidenceRefreshTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @settings = {
      "approval_reference" => "test-only-fixture-approval", "subscription_verified" => true,
      "paid_quotes" => true, "automated_read" => true, "private_display" => true, "cache_storage" => true,
      "daily_request_budget" => 2, "retention_seconds" => 3600, "freshness_seconds" => 900
    }
    @entitlement = entitlement(@settings)
    @connection = EquiblesConnection.create!(user: @user)
    @snapshot = {
      "provider" => "equibles", "instrument" => "AAPL", "price" => "215.33", "currency" => "USD",
      "source_at" => 15.minutes.ago.iso8601, "received_at" => Time.current.iso8601,
      "quality" => "delayed", "decision_eligible" => false
    }
  end

  test "default and incomplete rights fail closed without provider spend" do
    assert_not EquiblesEntitlement.new(@user).approved?
    EquiblesEntitlement::REQUIRED.each do |right|
      assert_not entitlement(@settings.except(right)).approved?
    end
    assert_not refresh(entitlement: entitlement({}))
    assert_equal "rights_unverified", @connection.reload.last_error
    assert_equal 0, @connection.requests_used
  end

  test "encryption is mandatory and credential never stored in plaintext" do
    EquiblesConnection.stub(:encryption_configured?, false) do
      assert_not refresh
      assert_equal "encryption_unavailable", @connection.reload.last_error
    end
    with_credentials do
      raw = EquiblesConnection.connection.select_value("SELECT api_key FROM equibles_connections WHERE id = #{@connection.id}")
      refute_includes raw, "eq_test_personal_key"
      assert_equal "eq_test_personal_key", @connection.reload.api_key
      refute_includes @connection.inspect, "eq_test_personal_key"
    end
  end

  test "success persists only evidence and duplicate requests consume no quota" do
    with_credentials do
      assert refresh
      before = @connection.reload.snapshot
      assert_equal 1, @connection.requests_used
      assert_not refresh
      assert_equal "duplicate_refresh", @connection.reload.last_error
      assert_equal 1, @connection.requests_used
      assert_equal before, @connection.snapshot
      assert_equal false, @connection.snapshot.dig("entitlement", "decision_eligible")
    end
  end

  test "failed refresh retains original source received and success times" do
    with_credentials do
      assert refresh
      before = @connection.reload.attributes.slice("snapshot", "last_success_at")
      @connection.update!(last_attempt_at: 61.seconds.ago)
      assert_not refresh(error: "provider_quota")
      assert_equal before, @connection.reload.attributes.slice("snapshot", "last_success_at")
      assert_equal 2, @connection.requests_used
      @connection.update!(last_attempt_at: 61.seconds.ago)
      assert_not refresh
      assert_equal "local_quota", @connection.reload.last_error
      assert_equal 2, @connection.requests_used
    end
  end

  test "quota resets at UTC midnight and invalid input never spends" do
    with_credentials do
      assert_not refresh(ticker: ["AAPL"])
      assert_equal 0, @connection.reload.requests_used
      @connection.update!(quota_date: Date.yesterday, requests_used: 2)
      assert refresh
      assert_equal Time.current.utc.to_date, @connection.reload.quota_date
      assert_equal 1, @connection.requests_used
    end
  end

  test "retention expiry and permission revocation purge evidence" do
    with_credentials do
      assert refresh
      @connection.update!(last_success_at: 3601.seconds.ago, last_attempt_at: 61.seconds.ago)
      assert_not refresh(error: "transport_failure")
      assert_empty @connection.reload.snapshot
      @connection.update!(snapshot: @snapshot)
      assert_not refresh(entitlement: entitlement({}))
      assert_empty @connection.reload.snapshot
    end
  end

  test "database enforces one connection per user and restrictive foreign key" do
    assert_raises(ActiveRecord::RecordInvalid) { EquiblesConnection.create!(user: @user) }
    assert EquiblesConnection.connection.indexes(:equibles_connections).any? { |index| index.unique && index.columns == ["user_id"] }
    assert EquiblesConnection.connection.foreign_keys(:equibles_connections).any? { |key| key.to_table == "users" }
  end

  test "independent stale instances lock and reload before duplicate suppression" do
    with_credentials do
      stale_instance = EquiblesConnection.find(@connection.id)
      sql = []
      subscriber = ->(*args) { sql << args.last[:sql] }
      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { assert refresh }
      assert sql.any? { |statement| statement.include?("equibles_connections") && statement.include?("FOR UPDATE") }
      service = EquiblesEvidenceRefresh.new(
        stale_instance, entitlement: @entitlement,
        client_factory: ->(*) { flunk "Duplicate request from stale instance" }
      )
      assert_not service.call("AAPL")
      assert_equal "duplicate_refresh", stale_instance.reload.last_error
      assert_equal 1, stale_instance.requests_used
    end
  end

  test "optional policy expiry rejects invalid or elapsed approval and bounds stored evidence" do
    [nil, "", "tomorrow", "2026-01-01", 1.minute.ago.iso8601].each do |expiry|
      assert_not entitlement(@settings.merge("expires_at" => expiry)).approved?
    end
    approved_until = 10.minutes.from_now
    @entitlement = entitlement(@settings.merge("expires_at" => approved_until.iso8601))
    assert @entitlement.approved?
    with_credentials do
      assert refresh
      renewed = entitlement(@settings.merge("expires_at" => 1.hour.from_now.iso8601))
      @connection.with_lock do
        @connection.expire_evidence!(renewed, now: approved_until + 1.second)
      end
      assert_empty @connection.reload.snapshot
    end
  end

  test "changed display rights and shortened retention purge rather than expose old evidence" do
    with_credentials do
      assert refresh
      @connection.update!(last_success_at: 45.minutes.ago)
      shortened = entitlement(@settings.merge("retention_seconds" => 1800))
      @connection.with_lock { @connection.expire_evidence!(shortened) }
      assert_empty @connection.reload.snapshot

      @connection.update!(last_attempt_at: 61.seconds.ago)
      assert refresh
      revoked = entitlement(@settings.merge("private_display" => false))
      @connection.with_lock { @connection.expire_evidence!(revoked) }
      assert_empty @connection.reload.snapshot
    end
  end

  test "a later retention extension cannot lengthen the originally permitted retention" do
    with_credentials do
      assert refresh
      @connection.update!(last_success_at: 3601.seconds.ago)
      extended = entitlement(@settings.merge("retention_seconds" => 86_400))
      @connection.with_lock { @connection.expire_evidence!(extended) }
      assert_empty @connection.reload.snapshot
    end
  end

  private

  def entitlement(settings)
    EquiblesEntitlement.new(@user, configuration: { "verified_users" => { @user.id.to_s => settings } })
  end

  def refresh(entitlement: @entitlement, error: nil, ticker: "AAPL")
    client = Object.new
    snapshot = @snapshot.deep_dup
    client.define_singleton_method(:snapshot) do |*|
      raise EquiblesClient::EvidenceError, error if error
      snapshot
    end
    EquiblesEvidenceRefresh.new(@connection, entitlement: entitlement,
                               client_factory: ->(*) { client }).call(ticker)
  end

  def with_credentials
    # Fixed, non-production test key-provider; no operator secrets or config changes.
    provider = ActiveRecord::Encryption::KeyProvider.new(
      ActiveRecord::Encryption::Key.new("test-only-equibles-key-material!")
    )
    ActiveRecord::Encryption.with_encryption_context(key_provider: provider) do
      EquiblesConnection.stub(:encryption_configured?, true) do
        @connection.update!(api_key: "eq_test_personal_key")
        yield
      end
    end
  end
end
