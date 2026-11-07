ENV["RAILS_ENV"] ||= "test"
require_relative "../../config/environment"
require "minitest/autorun"
require "minitest/mock"
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
    assert_theme_control(doc)
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
    assert doc.at_css('#search-form form[data-turbo-frame="_top"]')
    assert doc.at_css('label[for="stock"]')
    assert_equal "submit", doc.at_css('#search-form button')["type"]
    assert_equal 1, doc.css("#search-form").length
    assert_equal 1, doc.css("#stocks-list").length
    assert_equal 1, doc.css("#flash").length
    toast = doc.at_css('#flash .toast[data-controller="alert"]')
    assert toast
    assert_equal "status", toast["role"]
    assert_equal "turbo:before-cache@document->alert#remove", toast["data-action"]
    assert toast.at_css('button[data-action="alert#dismiss"]')
    assert_theme_control(doc)
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

  def test_search_streams_replace_wrapped_frames_instead_of_nesting_duplicate_ids
    post "https://example.org/users/sign_in", user: { email: @user.email, password: "example-password" }
    stock = Stock.new(ticker: "SYNTH", name: "Synthetic test")
    Stock.stub(:new_lookup, stock) do
      2.times do
        get "https://example.org/search_stock", { stock: "SYNTH" }, { "HTTP_ACCEPT" => "text/vnd.turbo-stream.html" }
        assert_equal 200, last_response.status
        doc = Nokogiri::HTML.fragment(last_response.body)
        assert doc.at_css('turbo-stream[action="replace"][target="posts"] template turbo-frame#posts')
        assert_empty doc.css('turbo-stream[action="append"]')
      end
    end
    get "https://example.org/search_friend", { friend: "Example" }, { "HTTP_ACCEPT" => "text/vnd.turbo-stream.html" }
    assert_equal 200, last_response.status
    assert Nokogiri::HTML.fragment(last_response.body).at_css('turbo-stream[action="replace"][target="friend-result"]')
  end

  private

  def assert_theme_control(doc)
    assert_equal 1, doc.css("select[data-theme-selector]").length
    assert_equal %w[light grey dark], doc.css("select[data-theme-selector] option").map { |option| option["value"] }
    assert doc.at_css('label[for="appearance-theme"]')
    assert doc.at_css('[data-theme-control][hidden]')
    assert doc.at_css('#theme-status[role="status"]')
    theme_script = doc.at_css('head script[src*="/theme-"]')
    assert theme_script
    refute theme_script.key?("defer")
    refute theme_script.key?("async")
    head_children = doc.at_css("head").element_children
    assert_operator head_children.index(theme_script), :<, head_children.index(doc.at_css('head link[rel="stylesheet"]'))
  end
end
