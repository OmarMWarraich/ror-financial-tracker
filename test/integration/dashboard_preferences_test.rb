require "test_helper"

class DashboardPreferencesIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    https!
    @owner = users(:one).dup
    @owner.id = SecureRandom.random_number(1_000_000_000) + 1_000_000_000
    @owner.email = "original-ui-#{SecureRandom.hex(8)}@example.test"
    @owner.password = "Original-ui-preference-123"
    @owner.save!
    @redis = Redis.new(url: ENV.fetch("REDIS_URL"), timeout: 2)
    @key = DashboardPreferences.key(@owner)
    sign_in @owner
    @state = { "version" => 1, "ranges" => { "ALPHA" => "5D" }, "selected" => "ALPHA" }
  end

  teardown do
    @redis.del(@key) if @redis && @key
    @redis.close if @redis
  end

  test "authenticated UI preferences roundtrip in owner-scoped Redis with bounded expiry" do
    put dashboard_preferences_path, params: { preferences: @state }, as: :json
    assert_response :success
    assert_equal @state, response.parsed_body
    assert_equal @state, JSON.parse(@redis.get(@key))
    assert @redis.ttl(@key).between?(86_390, 86_400)
    get dashboard_preferences_path, as: :json
    assert_response :success
    assert_equal @state, response.parsed_body
    assert_equal "no-store", response.headers["Cache-Control"]
    sign_out @owner
    sign_in users(:two)
    get dashboard_preferences_path, as: :json
    assert_response :success
    assert_nil response.parsed_body["selected"]
    assert_empty response.parsed_body["ranges"]
    sign_out users(:two)
    get dashboard_preferences_path, as: :json
    assert_response :unauthorized
    put dashboard_preferences_path, params: { preferences: @state }, as: :json
    assert_response :unauthorized
  end

  test "rejects licensed payloads malformed shapes and excessive ranges without saving" do
    filtered = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters).filter("preferences" => @state)
    assert_equal "[FILTERED]", filtered["preferences"]
    invalid = [@state.merge("quotes" => [{ "price" => 100 }]), @state.merge("selected" => "../secret"),
      @state.merge("ranges" => { "ALPHA" => "2Y" }), @state.merge("ranges" => (1..11).to_h { |n| ["TEST#{n}", "1M"] }),
      ["invalid"], "invalid", nil]
    invalid.each do |state|
      put dashboard_preferences_path, params: { preferences: state }, as: :json
      assert_response :unprocessable_entity
      assert_nil @redis.get(@key)
    end
  end

  test "Redis failure is explicit and cannot look like a successful backup" do
    failed = Object.new
    failed.define_singleton_method(:read) { raise Redis::CannotConnectError, "original synthetic failure" }
    failed.define_singleton_method(:write) { |_| raise Redis::CannotConnectError, "original synthetic failure" }
    DashboardPreferences.stub(:new, ->(*) { failed }) do
      get dashboard_preferences_path, as: :json
      assert_response :service_unavailable
      assert_includes response.parsed_body["error"], "unavailable"
      put dashboard_preferences_path, params: { preferences: @state }, as: :json
      assert_response :service_unavailable
      assert_includes response.parsed_body["error"], "unavailable"
    end
  end

  test "preferences mutation requires the Rails session CSRF token" do
    previous = MarketDashboardsController.allow_forgery_protection
    exceptions = Rails.application.env_config["action_dispatch.show_exceptions"]
    MarketDashboardsController.allow_forgery_protection = true
    Rails.application.env_config["action_dispatch.show_exceptions"] = :none
    assert_raises(ActionController::InvalidAuthenticityToken) do
      put dashboard_preferences_path, params: { preferences: @state }, as: :json
    end
    assert_nil @redis.get(@key)
  ensure
    MarketDashboardsController.allow_forgery_protection = previous
    Rails.application.env_config["action_dispatch.show_exceptions"] = exceptions
  end
end
