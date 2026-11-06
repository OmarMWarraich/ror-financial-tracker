ENV["RAILS_ENV"] ||= "test"
require_relative "../../config/environment"
require "minitest/autorun"
require "rack/test"

class ApplicationShellTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Rails.application
  end

  def setup
    ActiveRecord::Base.connection.begin_transaction(joinable: false)
    @user = User.create!(email: "shell-#{SecureRandom.hex(6)}@example.test", password: "example-password",
                         first_name: "Example", last_name: "Reviewer")
  end

  def teardown
    ActiveRecord::Base.connection.rollback_transaction
    clear_cookies
  end

  def test_public_shell_has_supported_navigation_and_unique_main_and_flash
    get "/portfolio_demo"
    assert_equal 200, last_response.status
    doc = Nokogiri::HTML(last_response.body)
    assert_equal 1, doc.css("main").length
    assert_equal 1, doc.css("#flash").length
    assert_equal "en", doc.at_css("html")["lang"]
    assert_equal "/portfolio_demo", doc.at_css('nav a[aria-current="page"]')["href"]
    assert doc.at_css('a[href="#main-content"]')
    assert doc.at_css('button[aria-controls="application-navigation"]')
    assert_empty doc.css('nav a[href="/broker_connections"]')
    assert_empty doc.css('[data-bs-toggle], [data-bs-dismiss]')
    refute_includes doc.text, "Another action"
    assert doc.at_css('link[href*="tailwind"]')
    assert doc.at_css('script[type="importmap"]')
  end

  def test_authenticated_shell_keeps_profile_signout_and_search_contracts
    post "https://example.org/users/sign_in", user: { email: @user.email, password: "example-password" }
    assert_equal 303, last_response.status
    get "https://example.org/my_portfolio"
    assert_equal 200, last_response.status
    doc = Nokogiri::HTML(last_response.body)
    assert doc.at_css('nav a[href="/broker_connections"]')
    assert doc.at_css('a[href="/users/edit"]')
    assert doc.at_css('a[href="/users/sign_out"][data-turbo-method="delete"]')
    assert doc.at_css('#search-form form[action="/search_stock"][method="get"]')
    assert doc.at_css('label[for="stock"]')
    assert_equal "submit", doc.at_css('#search-form button')["type"]
    assert_equal 1, doc.css("#search-form").length
    assert_equal 1, doc.css("#stocks-list").length
    assert_equal 1, doc.css("#flash").length
  end

  def test_authentication_form_is_unchanged
    get "https://example.org/users/sign_in"
    assert_equal 200, last_response.status
    doc = Nokogiri::HTML(last_response.body)
    assert doc.at_css('form[action="/users/sign_in"][method="post"]')
    assert doc.at_css('input[name="user[email]"]')
    assert doc.at_css('input[name="user[password]"][autocomplete="current-password"]')
    assert doc.at_css('input[name="user[remember_me]"][type="checkbox"]')
  end

end
