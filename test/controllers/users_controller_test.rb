require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  test "private read routes require authentication" do
    [root_path, my_portfolio_path, my_friends_path, user_path(users(:two)),
     search_stock_path(stock: "AAPL"), search_friend_path(friend: "Bob")].each do |path|
      get path
      assert_redirected_to new_user_session_path
    end
  end

  test "portfolio renders assets and only the signed in user's watchlist" do
    sign_in users(:one)
    get my_portfolio_path
    assert_response :success
    assert_select 'link[rel="stylesheet"]'
    assert_select "td", text: "Apple Inc."
    assert_select "td", text: "Microsoft Corporation", count: 0
    assert_select "a[data-turbo-method='delete']", text: "Remove", count: 1
  end

  test "friends view lists only the signed in user's friends" do
    sign_in users(:one)
    get my_friends_path
    assert_response :success
    assert_select "th", text: users(:two).email
    assert_select "th", text: users(:three).email, count: 0
  end

  test "authenticated friend profile exposes watchlist without removal authority" do
    sign_in users(:one)
    get user_path(users(:two))
    assert_response :success
    assert_select "td", text: "Microsoft Corporation"
    assert_select "a[data-turbo-method='delete']", text: "Remove", count: 0
    assert_select "a[data-turbo-method='post']", text: "Add to portfolio"
  end

  test "friend search returns matching users but not the current user" do
    sign_in users(:one)
    get search_friend_path, params: { friend: "example.test" }, as: :turbo_stream
    assert_response :success
    assert_includes response.body, users(:two).email
    assert_not_includes response.body, users(:one).email
  end
end
