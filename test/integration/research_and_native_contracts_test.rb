require "test_helper"

class ResearchAndNativeContractsTest < ActionDispatch::IntegrationTest
  test "public lab has only fixture observations and no provider requests" do
    Net::HTTP.stub(:start, ->(*) { flunk "No model or provider request permitted" }) do
      get research_demo_path
      assert_response :success
      assert_select "h1", "Synthetic research policy lab"
      assert_select '[data-testid="research-result"]', /no order/
      assert_select 'input[type="password"]', count: 0
      get research_demo_path, params: { scenario: "injection" }
      assert_response :success
      assert_select '[data-testid="research-result"]', /Unknown or missing/
    end
    [["valid"], "unlisted"].each do |scenario|
      get research_demo_path, params: { scenario: scenario }
      assert_response :bad_request
    end
  end

  test "both native contracts are public versioned navigation data not authorization" do
    %w[ios android].each do |platform|
      get "/configurations/#{platform}_v1.json"
      assert_response :success
      data = response.parsed_body
      assert_equal 1, data.fetch("settings").fetch("schema_version")
      assert_equal false, data.fetch("settings").fetch("live_execution")
      defaults = data.fetch("rules").first.fetch("properties")
      assert_equal false, defaults.fetch("pull_to_refresh_enabled")
      if platform == "android"
        assert_equal "hotwire://fragment/web", defaults["uri"]
        assert_equal "hotwire://fragment/web/modal/sheet", data.fetch("rules").last.fetch("properties").fetch("uri")
      end
    end
    get "/broker_connections", headers: { "User-Agent" => "Hotwire Native iOS" }
    assert_redirected_to new_user_session_path
    get "/configurations/other_v1.json"
    assert_response :not_found
  end
end
