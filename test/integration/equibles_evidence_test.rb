require "test_helper"
require "minitest/mock"

class EquiblesEvidenceTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @other = users(:two)
    https!
    sign_in @user
    @settings = {
      "approval_reference" => "test-only-private-display", "subscription_verified" => true,
      "paid_quotes" => true, "automated_read" => true, "private_display" => true, "cache_storage" => true,
      "daily_request_budget" => 2, "retention_seconds" => 3600, "freshness_seconds" => 900
    }
  end

  test "all evidence endpoints require authentication" do
    sign_out @user
    Net::HTTP.stub(:start, ->(*) { flunk "Unauthenticated provider request" }) do
      get equibles_evidence_path
      assert_redirected_to new_user_session_path
      patch equibles_evidence_path, params: { api_key: "eq_test_personal_key", current_password: "password123" }
      assert_redirected_to new_user_session_path
      post refresh_equibles_evidence_path, params: { ticker: "AAPL" }
      assert_redirected_to new_user_session_path
      delete equibles_evidence_path, params: { current_password: "password123" }
      assert_redirected_to new_user_session_path
    end
  end

  test "default gate never spends or stores a key even with a valid application password" do
    Net::HTTP.stub(:start, ->(*) { flunk "Unknown permissions must not spend quota" }) do
      get equibles_evidence_path
      assert_response :success
      assert_equal "no-store", response.headers["Cache-Control"]
      assert_select '[role="alert"]', text: /Disabled: subscription/
      assert_select 'input[name="api_key"]', count: 0
      assert_no_difference "EquiblesConnection.count" do
        patch equibles_evidence_path, params: { api_key: "eq_test_personal_key", current_password: "password123" }
      end
      assert_redirected_to equibles_evidence_path
      assert_includes flash[:alert], "rights or encryption"
      post refresh_equibles_evidence_path, params: { ticker: "AAPL" }
      assert_redirected_to equibles_evidence_path
    end
  end

  test "approved key mutation requires real password step up and stays scoped to session user" do
    with_approved_encryption do
      assert_no_difference "EquiblesConnection.count" do
        patch equibles_evidence_path, params: {
          api_key: "eq_test_personal_key", current_password: "incorrect", user_id: @other.id
        }
      end
      assert_includes flash[:alert], "password"
      assert_difference "EquiblesConnection.count", 1 do
        patch equibles_evidence_path, params: {
          api_key: "eq_test_personal_key", current_password: "password123", user_id: @other.id
        }
      end
      connection = EquiblesConnection.find_by!(user: @user)
      assert_nil EquiblesConnection.find_by(user: @other)
      assert_equal "eq_test_personal_key", connection.api_key
      refute_includes connection.api_key_before_type_cast, "eq_test_personal_key"
      get equibles_evidence_path
      assert_response :success
      refute_includes response.body, "eq_test_personal_key"
      assert_select 'input[name="api_key"][value]', count: 0

      delete equibles_evidence_path, params: { current_password: "incorrect", user_id: @other.id }
      assert_equal "eq_test_personal_key", connection.reload.api_key
      delete equibles_evidence_path, params: { current_password: "password123", user_id: @other.id }
      assert_nil connection.reload.api_key
      assert_empty connection.snapshot
    end
  end

  test "refresh reads one private quote and failed refresh preserves original evidence" do
    with_approved_encryption do
      connection = EquiblesConnection.create!(user: @user, api_key: "eq_test_personal_key")
      requests = []
      success = Net::HTTPOK.new("1.1", "200", "OK")
      body = JSON.generate(ticker: "BRK-B", currency: "USD", price: 450.1234, stale: false,
                           delayed: true, asOf: 15.minutes.ago.iso8601)
      success.define_singleton_method(:body) { body }
      with_provider_response(success, requests) do
        post refresh_equibles_evidence_path, params: { ticker: "brk.b", user_id: @other.id }
      end
      assert_redirected_to equibles_evidence_path
      assert_equal 1, requests.length
      assert_equal "/v1/stocks/BRK-B/quote", requests.first.uri.path
      assert_equal "Bearer eq_test_personal_key", requests.first["Authorization"]
      assert_equal "BRK-B", connection.reload.snapshot["instrument"]
      assert_equal "delayed", connection.snapshot["quality"]
      old_evidence = connection.attributes.slice("snapshot", "last_success_at")

      connection.update!(last_attempt_at: 61.seconds.ago)
      with_provider_response(Net::HTTPTooManyRequests.new("1.1", "429", "Limited"), requests) do
        post refresh_equibles_evidence_path, params: { ticker: "BRK-B" }
      end
      assert_includes flash[:alert], "Provider quota"
      assert_equal old_evidence, connection.reload.attributes.slice("snapshot", "last_success_at")
      get equibles_evidence_path
      assert_select '[role="alert"]', text: /Provider quota/
      assert_select "dd", text: "450.1234 USD"
    end
  end

  test "another user's identity parameters cannot expose or refresh private evidence" do
    with_approved_encryption do
      connection = EquiblesConnection.create!(user: @user, api_key: "eq_test_personal_key",
                                             snapshot: { "instrument" => "PRIVATE-EVIDENCE" })
      sign_out @user
      sign_in @other
      Net::HTTP.stub(:start, ->(*) { flunk "Another user's provider connection must not be used" }) do
        get equibles_evidence_path, params: { user_id: @user.id, id: connection.id }
        assert_response :success
        refute_includes response.body, "PRIVATE-EVIDENCE"
        post refresh_equibles_evidence_path, params: { user_id: @user.id, id: connection.id, ticker: "AAPL" }
        assert_redirected_to equibles_evidence_path
        delete equibles_evidence_path, params: { user_id: @user.id, id: connection.id, current_password: "password123" }
      end

      assert_equal "eq_test_personal_key", connection.reload.api_key
      assert_equal "PRIVATE-EVIDENCE", connection.snapshot["instrument"]
    end
  end

  test "missing encryption hides retained evidence and fails refresh without decrypting credentials" do
    with_approved_encryption do
      EquiblesConnection.create!(
        user: @user, api_key: "eq_test_personal_key", last_success_at: Time.current,
        snapshot: { "instrument" => "PRIVATE-EVIDENCE", "entitlement" => { "retention_seconds" => 3600 } }
      )
      @encryption_ready = false
      Net::HTTP.stub(:start, ->(*) { flunk "Missing encryption must not call provider" }) do
        get equibles_evidence_path
        assert_response :success
        assert_equal "no-store", response.headers["Cache-Control"]
        refute_includes response.body, "PRIVATE-EVIDENCE"
        assert_select '[role="alert"]', text: /encryption keys are not configured/
        post refresh_equibles_evidence_path, params: { ticker: "AAPL" }
        assert_redirected_to equibles_evidence_path
        assert_includes flash[:alert], "Encryption unavailable"
      end
    end
  end

  test "legacy search and tracking never copy private quote prices into shared stocks" do
    with_approved_encryption do
      EquiblesConnection.create!(
        user: @user, api_key: "eq_test_personal_key", last_success_at: Time.current,
        snapshot: {
          "instrument" => "BRK-B", "price" => "450.1234", "provider" => "equibles",
          "entitlement" => { "retention_seconds" => 3600 }
        }
      )
      Net::HTTP.stub(:start, ->(*) { flunk "Legacy watchlist must not spend provider quota" }) do
        get search_stock_path, params: { stock: "brk.b" }, as: :turbo_stream
        assert_response :success
        refute_includes response.body, "450.1234"
        assert_difference "Stock.count", 1 do
          post user_stocks_path, params: { ticker: "brk.b", user_id: @other.id }
        end
      end
      stock = Stock.check_db("BRK-B")
      assert_equal "BRK-B", stock.name
      assert_nil stock.last_price
      assert @user.stocks.exists?(stock.id)
      assert_not @other.stocks.exists?(stock.id)
      assert_equal 0, @user.equibles_connection.requests_used
    end
  end

  test "refresh rejects a missing CSRF token when forgery protection is enabled" do
    previous = EquiblesEvidenceController.allow_forgery_protection
    exceptions = Rails.application.env_config["action_dispatch.show_exceptions"]
    EquiblesEvidenceController.allow_forgery_protection = true
    Rails.application.env_config["action_dispatch.show_exceptions"] = :none
    assert_raises(ActionController::InvalidAuthenticityToken) do
      post refresh_equibles_evidence_path, params: { ticker: "AAPL" }
    end
  ensure
    EquiblesEvidenceController.allow_forgery_protection = previous
    Rails.application.env_config["action_dispatch.show_exceptions"] = exceptions
  end

  test "legacy stored quote values are hidden on owner social search and Hotwire surfaces" do
    stocks(:one).update!(last_price: 987654.32)
    stocks(:two).update!(last_price: 876543.21)
    Net::HTTP.stub(:start, ->(*) { flunk "Shared views must not request quotes" }) do
      [my_portfolio_path, user_path(@other)].each do |path|
        get path
        assert_response :success
        refute_includes response.body, "987654.32"
        refute_includes response.body, "876543.21"
        assert_select '[data-testid="shared-quote-unavailable"]', text: "Unavailable"
      end

      post user_stocks_path, params: { ticker: "MSFT" }, as: :turbo_stream
      assert_response :success
      refute_includes response.body, "987654.32"
      refute_includes response.body, "876543.21"
      assert_includes response.body, "Unavailable"

      Stock.stub(:new_lookup, ->(*) { stocks(:one) }) do
        get search_stock_path, params: { stock: "AAPL" }, as: :turbo_stream
      end
      assert_response :success
      refute_includes response.body, "987654.32"
      assert_includes response.body, "Unavailable"
    end
  end

  test "nil and legacy zero prices are explicitly unavailable rather than displayed as numbers" do
    stocks(:one).update!(last_price: nil)
    stocks(:two).update!(last_price: 0)
    @user.stocks << stocks(:two)
    get my_portfolio_path
    assert_response :success
    assert_select '[data-testid="shared-quote-unavailable"]', text: "Unavailable", count: 2
    assert_select "tbody tr" do
      assert_select "td:nth-of-type(2)", text: "0", count: 0
      assert_select "td:nth-of-type(2)", text: "0.0", count: 0
    end
  end

  private

  def with_approved_encryption
    entitlement_for = lambda do |user|
      EquiblesEntitlement.allocate.tap do |entitlement|
        entitlement.instance_variable_set(:@settings, user.id == @user.id ? @settings : {})
      end
    end
    key = ActiveRecord::Encryption::Key.new("test-only-equibles-key-material!")
    provider = ActiveRecord::Encryption::KeyProvider.new(key)
    ActiveRecord::Encryption.with_encryption_context(key_provider: provider) do
      EquiblesConnection.stub(:encryption_configured?, -> { @encryption_ready != false }) do
        EquiblesEntitlement.stub(:new, entitlement_for) { yield }
      end
    end
  end

  def with_provider_response(response, requests)
    transport = Object.new
    transport.define_singleton_method(:request) { |request| requests << request; response }
    Net::HTTP.stub(:start, ->(*, **, &block) { block.call(transport) }) { yield }
  end
end
