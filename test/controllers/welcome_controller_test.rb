require "test_helper"

class WelcomeControllerTest < ActionDispatch::IntegrationTest
  test "authenticated welcome page renders" do
    sign_in users(:one)
    get root_path
    assert_response :success
    assert_select "h1", "Your financial engineering workspace"
    assert_select "a[href=?]", portfolio_demo_path, text: "Explore demo dashboard"
  end

  test "Devise sign in authenticates valid fixture credentials" do
    post user_session_path, params: { user: { email: users(:one).email, password: "password123" } }
    assert_redirected_to root_path
    get my_portfolio_path
    assert_response :success
  end

  test "invalid Devise credentials do not grant private access" do
    post user_session_path, params: { user: { email: users(:one).email, password: "incorrect" } }
    assert_response :unprocessable_entity
    get my_portfolio_path
    assert_redirected_to new_user_session_path
  end

  test "sign out removes private access" do
    sign_in users(:one)
    delete destroy_user_session_path
    get my_portfolio_path
    assert_redirected_to new_user_session_path
  end
end
