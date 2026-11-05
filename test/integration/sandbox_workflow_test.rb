require_relative "../sandbox_test_support"
require "rack/test"

class SandboxWorkflowTest < Minitest::Test
  include Rack::Test::Methods
  include SandboxTestSupport

  def app
    Rails.application
  end

  def teardown
    clear_cookies
    super
  end

  def test_authentication_owner_scope_and_private_transport
    get "https://example.org/sandbox_accounts/#{@account.id}"
    assert_equal 302, last_response.status
    login(@other)
    get "https://example.org/sandbox_accounts/#{@account.id}"
    assert_equal 404, last_response.status
    post "https://example.org/sandbox_accounts/#{@account.id}/load_fixture", fixture_key: "fall-v1"
    assert_equal 404, last_response.status
    login(@owner)
    get "http://example.org/sandbox_accounts/#{@account.id}"
    assert_equal 403, last_response.status
    get "https://example.org/sandbox_accounts/#{@account.id}"
    assert_equal 200, last_response.status
    assert_includes last_response.headers["cache-control"], "no-store"
    assert_equal "no-referrer", last_response.headers["referrer-policy"]
    assert_includes last_response.body, "SYNTHETIC"
    assert_includes last_response.body, "Hand-authored fictional"
    refute_includes last_response.body, PASSWORD
    login(@owner, origin: "http://localhost")
    get "http://localhost/sandbox_accounts/#{@account.id}", {}, "REMOTE_ADDR" => "127.0.0.1"
    assert_equal 200, last_response.status
  end

  def test_owner_ui_draft_password_activation_evaluation_retry_pause_and_revoke
    login(@owner)
    post "https://example.org/sandbox_accounts/#{@account.id}/sandbox_mandates",
         sandbox_mandate: terms.transform_values { |value| value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone) ? value.iso8601 : value }
    assert_equal 302, last_response.status
    mandate = @account.sandbox_mandates.last
    assert_equal "draft", mandate.state
    transition(mandate, "active", "wrong")
    assert_equal "draft", mandate.reload.state
    transition(mandate, "active", PASSWORD)
    assert_equal "active", mandate.reload.state
    get "https://example.org/sandbox_accounts/#{@account.id}"
    assert_equal 200, last_response.status
    document = Nokogiri::HTML(last_response.body)
    execute_form = document.at_css('form[action$="/execute"]')
    refute_nil execute_form
    key = execute_form.at_css('input[name="request_key"]')["value"]
    2.times { post "https://example.org#{execute_form['action']}", request_key: key }
    assert_equal 1, @account.sandbox_orders.count
    transition(mandate, "paused")
    post "https://example.org#{execute_form['action']}", request_key: SecureRandom.uuid
    assert_equal 1, @account.sandbox_orders.count
    transition(mandate, "revoked")
    assert_equal "revoked", mandate.reload.state
    transition(mandate, "active", PASSWORD)
    assert_equal "revoked", mandate.reload.state
  end

  def test_execution_rejects_caller_prices_models_and_arbitrary_rules
    mandate = activate
    login(@owner)
    post "https://example.org/sandbox_accounts/#{@account.id}/sandbox_mandates/#{mandate.id}/execute",
         request_key: SecureRandom.uuid, price: 1, model: "BUY", provider: "private"
    assert_equal 302, last_response.status
    assert_empty @account.sandbox_orders
    post "https://example.org/sandbox_accounts/#{@account.id}/sandbox_mandates",
         sandbox_mandate: { rule_version: "arbitrary", code: "exec" }
    assert_equal 302, last_response.status
    assert_equal 1, @account.sandbox_mandates.count
  end

  def test_csrf_required_for_mutations_and_real_form_token_works
    login(@owner)
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    post "https://example.org/sandbox_accounts/#{@account.id}/load_fixture", fixture_key: "fall-v1"
    assert_equal 422, last_response.status
    assert_equal "rise-v1", @account.reload.fixture_key
    get "https://example.org/sandbox_accounts/#{@account.id}"
    document = Nokogiri::HTML(last_response.body)
    form = document.at_css('form[action$="/load_fixture"]')
    refute_nil form
    token = form.at_css('input[name="authenticity_token"]')["value"]
    post "https://example.org#{form['action']}", fixture_key: "fall-v1", authenticity_token: token
    assert_equal 302, last_response.status
    assert_equal "fall-v1", @account.reload.fixture_key
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  def test_new_account_form_and_password_confirmation_are_required
    login(@other)
    get "https://example.org/sandbox_accounts"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Create independent synthetic account"
    assert_includes last_response.body, "this synthetic ledger and its audit records are append-only"
    assert_includes last_response.body, "cannot be reset or deleted through ordinary account deletion"
    assert_match(/reviewed retention and account-closure\s+process remains unavailable/, last_response.body)
    post "https://example.org/sandbox_accounts", initial_cash: 500, current_password: "wrong"
    refute SandboxAccount.exists?(user_id: @other.id)
    post "https://example.org/sandbox_accounts", initial_cash: 500, current_password: PASSWORD
    assert_equal 302, last_response.status
    assert_equal 500, SandboxAccount.find_by!(user_id: @other.id).cash
  end

  private

  def login(user, origin: "https://example.org")
    clear_cookies
    post "#{origin}/users/sign_in", user: { email: user.email, password: PASSWORD }
    assert_equal 303, last_response.status
  end

  def transition(mandate, state, password = nil)
    patch "https://example.org/sandbox_accounts/#{@account.id}/sandbox_mandates/#{mandate.id}/transition",
          state: state, current_password: password
    assert_equal 302, last_response.status
  end
end
