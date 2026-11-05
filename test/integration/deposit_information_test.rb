ENV["RAILS_ENV"] ||= "test"
require_relative "../../config/environment"
require "minitest/autorun"
require "minitest/mock"
require "rack/test"

class DepositInformationTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Rails.application
  end

  def setup
    ActiveRecord::Base.connection.begin_transaction(joinable: false)
    @owner = User.create!(email: "deposit-owner-#{SecureRandom.hex(5)}@example.test", password: "example-password")
    @other = User.create!(email: "deposit-other-#{SecureRandom.hex(5)}@example.test", password: "example-password")
  end

  def teardown
    ActiveRecord::Base.connection.rollback_transaction
    clear_cookies
  end

  def test_owner_authentication_disabled_status_no_store_and_no_credentials_or_destinations
    get "https://example.org/deposit_information"
    assert_equal 302, last_response.status
    login(@owner)
    Net::HTTP.stub(:start, ->(*) { flunk "No implicit provider request" }) do
      get "https://example.org/deposit_information", user_id: @other.id
    end
    assert_equal 200, last_response.status
    assert_includes last_response.headers["cache-control"], "no-store"
    assert_equal "no-referrer", last_response.headers["referrer-policy"]
    assert_includes last_response.body, "Disabled"
    assert_includes last_response.body, "No owner is provider-verified"
    refute_includes last_response.body, @other.email
    html = Nokogiri::HTML(last_response.body)
    assert_empty html.css('input[name*="api_key"], input[name*="api_secret"], input[name*="seed"]')
    assert_empty html.css('input[type="password"][value], a[href^="bitcoin:"], a[href^="ethereum:"]')
    password = html.at_css('input[type="password"]')
    assert_equal "20", password["size"]
    assert_equal "1024", password["maxlength"]
    assert_includes password["class"].split, "form-control"
    assert_includes password["style"], "max-width: 100%"
    assert_includes html.at_css('label[for="current_password"]')["style"], "overflow-wrap: anywhere"
    button = password.ancestors("form").first.at_css('button[type="submit"]')
    assert_includes button["style"], "max-width: 100%"
    assert_includes button["style"], "white-space: normal"
  end

  def test_application_password_is_per_request_and_never_grants_approval
    login(@owner)
    Net::HTTP.stub(:start, ->(*) { flunk "Status checks must not request Kraken" }) do
      post "https://example.org/deposit_information/check", current_password: "wrong"
      assert_equal 422, last_response.status
      assert_equal 1, @owner.reload.sensitive_action_failures
      refute_includes last_response.body, 'value="wrong"'
      post "https://example.org/deposit_information/check", current_password: "example-password",
           user_id: @other.id, enabled: true, state: "verified"
      assert_equal 200, last_response.status
      assert_includes last_response.body, "no approval was granted"
      assert_equal 0, @owner.reload.sensitive_action_failures
      assert_equal 0, @other.reload.sensitive_action_failures
      post "https://example.org/deposit_information/check"
      assert_equal 422, last_response.status
    end
    assert_includes last_response.headers["cache-control"], "no-store"
  end

  def test_sensitive_action_lockout_is_reused_and_no_owner_can_enable_reads
    login(@owner)
    5.times { post "https://example.org/deposit_information/check", current_password: "wrong" }
    assert_operator @owner.reload.sensitive_action_locked_until, :>, Time.current
    post "https://example.org/deposit_information/check", current_password: "example-password"
    assert_equal 422, last_response.status
    assert_includes last_response.headers["cache-control"], "no-store"
    login(@other)
    post "https://example.org/deposit_information/check", current_password: "example-password"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Capability remains disabled"
  end

  def test_csrf_and_private_transport_are_required
    login(@owner)
    get "http://example.org/deposit_information"
    assert_equal 403, last_response.status
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    post "https://example.org/deposit_information/check", current_password: "example-password"
    assert_equal 422, last_response.status
    assert_equal 0, @owner.reload.sensitive_action_failures
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end

  private

  def login(user)
    clear_cookies
    post "https://example.org/users/sign_in", user: { email: user.email, password: "example-password" }
    assert_equal 303, last_response.status
  end
end
