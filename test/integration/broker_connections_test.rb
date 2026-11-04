ENV["RAILS_ENV"] ||= "test"
require_relative "../../config/environment"
require "minitest/autorun"
require "minitest/mock"
require "rack/test"

class BrokerConnectionsTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Rails.application
  end

  def setup
    @encryption_env = %w[ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY
                         ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT].to_h { |name| [name, ENV[name]] }
    @encryption_env.keys.each { |name| ENV[name] = "test-only-" + "a" * 32 }
    ActiveRecord::Encryption.configure(primary_key: ENV.fetch("ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"),
                                      deterministic_key: ENV.fetch("ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"),
                                      key_derivation_salt: ENV.fetch("ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"))
    ActiveRecord::Base.connection.begin_transaction(joinable: false)
    @owner = User.create!(email: "monitor-owner-#{SecureRandom.hex(5)}@example.test", password: "example-password")
    @other = User.create!(email: "monitor-other-#{SecureRandom.hex(5)}@example.test", password: "example-password")
    @key = "fakeKey" + SecureRandom.hex(24)
    @secret = Base64.strict_encode64("fake secret for offline tests only" * 2)
    @connection = @owner.broker_connections.create!(label: "Private test", api_key: @key, api_secret: @secret,
                                                    expires_at: 30.days.from_now)
  end

  def teardown
    ActiveRecord::Base.connection.rollback_transaction
    @encryption_env.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
    clear_cookies
  end

  def test_authentication_default_gate_and_no_secret_redisplay
    get "https://example.org/broker_connections"
    assert_equal 302, last_response.status
    login(@owner)
    Net::HTTP.stub(:start, ->(*) { flunk "No implicit broker requests" }) do
      get "https://example.org/broker_connections"
    end
    assert_equal 200, last_response.status
    assert_includes last_response.headers["cache-control"], "no-store"
    assert_includes last_response.body, "Setup blocked"
    refute_includes last_response.body, @key
    refute_includes last_response.body, @secret
    assert Nokogiri::HTML(last_response.body).at_css("fieldset[disabled]")
    assert_empty Nokogiri::HTML(last_response.body).css('input[type="password"][value]')
  end

  def test_secrets_and_account_evidence_are_encrypted_and_redacted
    @connection.update!(account_identifier: "OWN PRIVATE ACCOUNT",
                        balance_payload: JSON.generate([{ "private" => "value" }]))
    raw = ActiveRecord::Base.connection.select_one("SELECT api_key, api_secret, account_identifier, balance_payload FROM broker_connections WHERE id = #{@connection.id}")
    refute_includes raw["api_key"], @key
    refute_includes raw["api_secret"], @secret
    refute_includes raw["account_identifier"], "OWN PRIVATE ACCOUNT"
    refute_includes raw["balance_payload"], "private"
    assert_equal @key, @connection.reload.api_key
    filtered = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
      .filter("api_key" => @key, "api_secret" => @secret, "current_password" => "example-password",
              "account_identifier" => "account", "balance_payload" => "balances")
    assert filtered.values.all? { |value| value == "[FILTERED]" }
    refute_includes @connection.inspect, @secret
  end

  def test_missing_encryption_and_expired_owner_approval_fail_closed
    @connection.update!(balance_payload: JSON.generate([{ "provider_instrument_id" => "PRIVATEASSET" }]))
    login(@owner)
    ENV.delete("ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY")
    get "https://example.org/broker_connections"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Encrypted evidence unavailable"
    refute_includes last_response.body, "PRIVATEASSET"

    [{ enabled: false, approved_users: {} },
     { enabled: true, approved_users: {} },
     { enabled: true, approved_users: nil },
     { enabled: true, approved_users: { @owner.id.to_s => { reference: "test-review", expires_at: 1.day.ago.iso8601 } } },
     { enabled: true, approved_users: { @owner.id.to_s => { reference: "test-review", expires_at: "invalid" } } }].each do |settings|
      Rails.application.stub(:config_for, settings) { refute KrakenMonitoringPolicy.approved?(@owner) }
    end
    settings = { enabled: true, approved_users: { @owner.id.to_s => { reference: "test-review", expires_at: 1.day.from_now.iso8601 } } }
    Rails.application.stub(:config_for, settings) do
      assert KrakenMonitoringPolicy.approved?(@owner)
      refute KrakenMonitoringPolicy.approved?(@other)
    end
    Net::HTTP.stub(:start, ->(*) { flunk "Disabled monitoring must not request the provider" }) do
      assert_raises(KrakenReadOnlyClient::Error) { KrakenMonitoringRefresh.call(@connection) }
    end
  end

  def test_cross_owner_routes_are_denied_and_mass_assignment_cannot_change_authority
    login(@other)
    %w[refresh request_elevation].each do |action|
      post "https://example.org/broker_connections/#{@connection.id}/#{action}", current_password: "example-password"
      assert_equal 404, last_response.status
    end
    delete "https://example.org/broker_connections/#{@connection.id}", current_password: "example-password"
    assert_equal 404, last_response.status
    assert_equal "pending", @connection.reload.state
    login(@owner)
    KrakenMonitoringPolicy.stub(:approved?, true) do
      post "https://example.org/broker_connections", current_password: "example-password", owns_account: "1",
        broker_connection: { label: "Owner-only", api_key: "newFakeKey" + SecureRandom.hex(12), api_secret: @secret,
                             user_id: @other.id, mode: "live", state: "verified", elevation_state: "active",
                             product: "securities" }
    end
    assert_equal 302, last_response.status
    connection = @owner.broker_connections.order(:id).last
    assert_equal "pending", connection.state
    assert_equal "read_only", connection.mode
    assert_equal "exchange", connection.product
    assert_equal "not_requested", connection.elevation_state
    assert_nil connection.received_at
    assert_equal 0, @other.broker_connections.count
  end

  def test_unreadable_encryption_is_an_explicit_failure_without_provider_dispatch
    login(@owner)
    ActiveRecord::Base.connection.execute("UPDATE broker_connections SET api_secret = 'corrupt-ciphertext' WHERE id = #{@connection.id}")
    KrakenMonitoringPolicy.stub(:approved?, true) do
      Net::HTTP.stub(:start, ->(*) { flunk "Unreadable credentials cannot dispatch" }) do
        post "https://example.org/broker_connections/#{@connection.id}/refresh"
      end
    end
    assert_equal 503, last_response.status
    assert_includes last_response.body, "Restore the original deployment encryption keys"
    assert_nil @connection.reload.received_at
  end

  def test_step_up_failure_lockout_and_missing_owner_consent_block_setup
    login(@owner)
    KrakenMonitoringPolicy.stub(:approved?, true) do
      5.times do
        post "https://example.org/broker_connections", current_password: "wrong", owns_account: "1",
          broker_connection: { label: "Denied", api_key: "anotherKey", api_secret: @secret }
        assert_equal 302, last_response.status
      end
      assert_operator @owner.reload.sensitive_action_locked_until, :>, Time.current
      post "https://example.org/broker_connections", current_password: "example-password", owns_account: "1",
        broker_connection: { label: "Still denied", api_key: "anotherKey", api_secret: @secret }
      assert_equal 1, @owner.broker_connections.count
      @owner.update!(sensitive_action_locked_until: 1.second.ago)
      post "https://example.org/broker_connections", current_password: "example-password",
        broker_connection: { label: "No ownership", api_key: "anotherKey", api_secret: @secret }
      assert_equal 1, @owner.broker_connections.count
    end
  end

  def test_refresh_pins_identity_bounds_requests_and_retains_old_evidence_on_failure
    nonces = []
    factory = ->(**arguments) do
      nonces << arguments.fetch(:nonce).call
      fake_client
    end
    KrakenMonitoringPolicy.stub(:approved?, true) do
      KrakenReadOnlyClient.stub(:new, factory) do
        KrakenMonitoringRefresh.call(@connection)
        assert_equal "verified", @connection.state
        assert_equal ["query-funds"], @connection.verified_permissions
        assert_equal "2.5", @connection.balances.first["quantity"]
        assert_equal "AA88 TEST ACCOUNT", @connection.account_identifier
        previous_time = @connection.received_at
        assert_raises(KrakenReadOnlyClient::Error) { KrakenMonitoringRefresh.call(@connection) }
        assert_equal 1, nonces.length
        assert_equal previous_time, @connection.received_at
        assert @connection.stale?
      end
      @connection.update!(last_attempt_at: 2.minutes.ago)
      failed = fake_client
      failed.define_singleton_method(:balances) { raise KrakenReadOnlyClient::Error, "Provider unavailable" }
      KrakenReadOnlyClient.stub(:new, failed) do
        before = @connection.received_at
        assert_raises(KrakenReadOnlyClient::Error) { KrakenMonitoringRefresh.call(@connection) }
        assert_equal before, @connection.received_at
        assert_equal "Provider unavailable", @connection.last_error
        assert_equal "2.5", @connection.balances.first["quantity"]
      end
      @connection.update!(last_attempt_at: 2.minutes.ago)
      swapped = fake_client
      swapped.define_singleton_method(:key_info) do |include_history:|
        { identifier: "ANOTHER ACCOUNT", permissions: ["query-funds"], expires_at: nil }
      end
      KrakenReadOnlyClient.stub(:new, swapped) do
        assert_raises(KrakenReadOnlyClient::PermissionError) { KrakenMonitoringRefresh.call(@connection) }
        assert_equal "blocked", @connection.reload.state
        assert_nil @connection.api_secret
        assert_equal "AA88 TEST ACCOUNT", @connection.account_identifier
      end
    end
  end

  def test_expiry_revocation_disconnect_and_delayed_work_never_reactivate
    @connection.update!(expires_at: 1.second.ago)
    KrakenMonitoringPolicy.stub(:approved?, true) do
      Net::HTTP.stub(:start, ->(*) { flunk "Inactive credentials must not be used" }) do
        assert_raises(KrakenReadOnlyClient::Error) { KrakenMonitoringRefresh.call(@connection) }
        assert_equal "expired", @connection.reload.state
        assert_nil @connection.api_key
      end
      @connection.update!(state: "revoked")
      assert_raises(KrakenReadOnlyClient::Error) { KrakenMonitoringRefresh.call(@connection) }
      @connection.disconnect!
      assert_equal "disconnected", @connection.reload.state
      assert_nil @connection.balance_payload
      assert_nil @connection.history_payload
      assert_raises(KrakenReadOnlyClient::Error) { KrakenMonitoringRefresh.call(@connection) }
      assert_equal "disconnected", @connection.reload.state
    end
  end

  def test_elevation_is_request_only_and_disconnect_requires_password
    login(@owner)
    @connection.update!(state: "verified")
    post "https://example.org/broker_connections/#{@connection.id}/request_elevation", current_password: "example-password"
    assert_equal 302, last_response.status
    assert_equal "requested", @connection.reload.elevation_state
    assert_equal "read_only", @connection.mode
    delete "https://example.org/broker_connections/#{@connection.id}", current_password: "wrong"
    assert_equal "verified", @connection.reload.state
    delete "https://example.org/broker_connections/#{@connection.id}", current_password: "example-password"
    assert_equal "disconnected", @connection.reload.state
    assert_nil @connection.api_key
    assert_nil @connection.api_secret
  end

  def test_concurrent_refreshes_serialize_nonce_and_suppress_duplicates
    with_committed_records do
      nonces = Queue.new
      results = Queue.new
      factory = ->(**arguments) do
        nonces << arguments.fetch(:nonce).call
        fake_client
      end
      KrakenMonitoringPolicy.stub(:approved?, true) do
        KrakenReadOnlyClient.stub(:new, factory) do
          workers = 2.times.map do
            Thread.new do
              ActiveRecord::Base.connection_pool.with_connection do
                KrakenMonitoringRefresh.call(BrokerConnection.find(@connection.id))
                results << :success
              rescue KrakenReadOnlyClient::Error
                results << :bounded
              end
            end
          end
          workers.each(&:value)
        end
      end
      assert_equal %i[bounded success], 2.times.map { results.pop }.sort
      assert_equal 1, nonces.size
      assert_equal nonces.pop, @connection.reload.last_nonce
      assert @connection.last_attempt_at
    end
  end

  def test_disconnect_coordinates_with_in_flight_read_and_removes_its_result
    with_committed_records do
      entered = Queue.new
      release = Queue.new
      completed = Queue.new
      fake = fake_client
      fake.define_singleton_method(:balances) do
        entered << true
        release.pop
        []
      end
      KrakenMonitoringPolicy.stub(:approved?, true) do
        KrakenReadOnlyClient.stub(:new, fake) do
          refresh = Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do
              KrakenMonitoringRefresh.call(BrokerConnection.find(@connection.id))
            end
          end
          Timeout.timeout(5) { entered.pop }
          disconnect = Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do
              BrokerConnection.find(@connection.id).disconnect!
              completed << true
            end
          end
          assert_raises(Timeout::Error) { Timeout.timeout(0.1) { completed.pop } }
          release << true
          [refresh, disconnect].each(&:value)
          assert_equal "disconnected", @connection.reload.state
          assert_nil @connection.api_secret
          assert_nil @connection.balance_payload
          assert_raises(KrakenReadOnlyClient::Error) { KrakenMonitoringRefresh.call(@connection) }
          assert_equal "disconnected", @connection.reload.state
        ensure
          release << true
          [refresh, disconnect].compact.each { |worker| worker.join(10) }
        end
      end
    end
  end

  def test_private_data_never_appears_in_demo_or_social_views
    @connection.update!(balance_payload: JSON.generate([{ "provider_instrument_id" => "PRIVATEASSET", "quantity" => "1234567.89" }]))
    login(@other)
    ["/portfolio_demo", "/users/#{@owner.id}", "/my_friends"].each do |path|
      get "https://example.org#{path}"
      assert_equal 200, last_response.status
      refute_includes last_response.body, "PRIVATEASSET"
      refute_includes last_response.body, @key
      refute_includes last_response.body, @secret
    end
  end

  def test_mutations_require_csrf_and_insecure_nonloopback_is_forbidden
    login(@owner)
    get "http://example.org/broker_connections"
    assert_equal 403, last_response.status
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    post "https://example.org/broker_connections/#{@connection.id}/refresh"
    assert_equal 422, last_response.status
    assert_nil @connection.reload.received_at
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end

  private

  def with_committed_records
    ActiveRecord::Base.connection.commit_transaction
    yield
  ensure
    @owner.broker_connections.destroy_all
    @owner.destroy!
    @other.destroy!
    ActiveRecord::Base.connection.begin_transaction(joinable: false)
  end

  def login(user)
    clear_cookies
    post "https://example.org/users/sign_in", user: { email: user.email, password: "example-password" }
    assert_equal 303, last_response.status
  end

  def fake_client
    client = Object.new
    client.define_singleton_method(:key_info) do |include_history:|
      { identifier: "AA88 TEST ACCOUNT", permissions: ["query-funds"], expires_at: nil }
    end
    client.define_singleton_method(:balances) do
      [{ "provider_instrument_id" => "UNCLASSIFIED", "quantity" => "2.5",
         "product_type" => "unclassified_exchange_asset", "analytics_supported" => false }]
    end
    client
  end
end
