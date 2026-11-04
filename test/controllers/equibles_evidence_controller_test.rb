require "test_helper"
require "minitest/mock"

class EquiblesEvidenceControllerTest < ActionController::TestCase
  include Devise::Test::ControllerHelpers
  tests EquiblesEvidenceController

  setup do
    @user = users(:one)
    @other = users(:two)
    # Route declarations remain coordinator-owned; exercise this controller with
    # the exact required contract without changing the application's routes.
    @routes = ActionDispatch::Routing::RouteSet.new
    @routes.draw do
      devise_for :users
      resource :equibles_evidence, only: %i[show update destroy], controller: "equibles_evidence" do
        post :refresh
      end
    end
    @controller.singleton_class.include @routes.url_helpers
    @controller.class.helper @routes.url_helpers
    @request.env["devise.mapping"] = Devise.mappings[:user]
    @request.host = "localhost"
    @request.env["REMOTE_ADDR"] = "127.0.0.1"
    @connection = EquiblesConnection.create!(user: @other)
  end

  test "authentication required for evidence and refresh" do
    get :show
    assert_redirected_to new_user_session_path
    post :refresh, params: { ticker: "AAPL" }
    assert_redirected_to new_user_session_path
  end

  test "unknown entitlement UI fails closed without provider calls" do
    sign_in @user
    Net::HTTP.stub(:start, ->(*) { flunk "Unexpected provider call" }) { get :show }
    assert_response :success
    assert_select "h1", "Private Equibles evidence"
    assert_select '[role="alert"]', text: /Disabled: subscription/
    assert_select 'input[name="api_key"]', count: 0
    assert_select "dd", count: 0
  end

  test "foreign connection ids are ignored and cannot refresh or disconnect another user" do
    sign_in @user
    before = @connection.attributes
    post :refresh, params: { ticker: "AAPL", id: @connection.id, user_id: @other.id }
    assert_redirected_to equibles_evidence_path
    assert_equal before, @connection.reload.attributes
    SensitiveActionAuthentication.stub(:verify, true) do
      delete :destroy, params: { id: @connection.id, user_id: @other.id }
    end
    assert_equal before, @connection.reload.attributes
  end

  test "personal key updates stay disabled without verified permissions" do
    sign_in @user
    SensitiveActionAuthentication.stub(:verify, true) do
      patch :update, params: { api_key: "eq_test_personal_key", user_id: @other.id }
    end
    assert_redirected_to equibles_evidence_path
    assert_nil EquiblesConnection.find_by(user_id: @user.id)
    assert_nil @connection.reload.api_key
  end

  test "disconnect requires step up" do
    sign_in @other
    SensitiveActionAuthentication.stub(:verify, false) { delete :destroy }
    assert_redirected_to equibles_evidence_path
    assert EquiblesConnection.exists?(@connection.id)
    assert_includes flash[:alert], "password"
  end

  test "production style insecure transport is forbidden" do
    sign_in @user
    @request.host = "example.com"
    get :show
    assert_response :forbidden
  end

  test "evidence writes inherit request forgery protection" do
    assert EquiblesEvidenceController < ApplicationController
    assert EquiblesEvidenceController._process_action_callbacks.any? { |callback| callback.filter == :verify_authenticity_token }
  end

  test "approved private evidence shows true source age and failed refresh without keys" do
    sign_in @other
    entitlement = EquiblesEntitlement.new(@other, configuration: {
      "verified_users" => { @other.id.to_s => {
        "approval_reference" => "test-only", "subscription_verified" => true, "paid_quotes" => true,
        "automated_read" => true, "private_display" => true, "cache_storage" => true,
        "daily_request_budget" => 2, "retention_seconds" => 3600, "freshness_seconds" => 900
      } }
    })
    @connection.update!(snapshot: {
      "provider" => "equibles", "instrument" => "BRK-B", "product_type" => "listed_security",
      "currency" => "USD", "price" => "450.1234", "source_at" => 2.hours.ago.iso8601,
      "received_at" => 1.minute.ago.iso8601, "delayed" => true, "quality" => "delayed",
      "session" => {}, "entitlement" => { "retention_seconds" => 3600 }
    }, last_success_at: 1.minute.ago, last_error: "provider_quota")
    success_at = @connection.reload.last_success_at
    EquiblesEntitlement.stub(:new, entitlement) do
      EquiblesConnection.stub(:encryption_configured?, true) { get :show }
    end
    assert_response :success
    assert_select "dd", text: "450.1234 USD"
    assert_select "dd", text: "Aged evidence"
    assert_select '[role="alert"]', text: /Provider quota/
    assert_select 'input[name="api_key"][value]', count: 0
    assert_select 'form[action="/equibles_evidence/refresh"]', count: 1
    assert_equal success_at, @connection.reload.last_success_at
  end

  test "refresh without CSRF token is rejected when forgery protection enabled" do
    sign_in @user
    previous = @controller.allow_forgery_protection
    @controller.allow_forgery_protection = true
    assert_raises(ActionController::InvalidAuthenticityToken) { post :refresh, params: { ticker: "AAPL" } }
  ensure
    @controller.allow_forgery_protection = previous
  end
end
