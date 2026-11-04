require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "tracking is scoped to the user's normalized ticker" do
    assert users(:one).stock_already_tracked?(" aapl ")
    assert_not users(:two).stock_already_tracked?("AAPL")
    assert_not users(:one).can_track_stock?("aapl")
    assert users(:two).can_track_stock?("AAPL")
    assert_not users(:one).stock_already_tracked?("UNKNOWN")
  end

  test "tracking allows nine stocks but not ten" do
    user = users(:one)
    8.times do |index|
      user.stocks.create!(ticker: "LIMIT#{index}", name: "Limit #{index}", last_price: 1)
    end
    assert user.under_stock_limit?
    assert user.can_track_stock?("MSFT")

    user.stocks << stocks(:two)
    assert_not user.under_stock_limit?
    assert_not user.can_track_stock?("UNTRACKED")
    assert users(:two).under_stock_limit?
  end

  test "search matches names and email and excludes the signed in user" do
    assert_includes User.search(" Alice "), users(:one)
    assert_includes User.search("Tracker"), users(:two)
    assert_includes User.search("carol@example.test"), users(:three)
    assert_empty users(:one).except_current_user(User.search("alice"))
  end

  test "friendships are directional and scoped to their owner" do
    assert_not users(:one).not_friends_with?(users(:two).id)
    assert users(:two).not_friends_with?(users(:one).id)
    assert users(:one).not_friends_with?(users(:three).id)
  end

  test "full name falls back for unnamed users" do
    assert_equal "Alice Investor", users(:one).full_name
    assert_equal "Anonymous", User.new.full_name
  end
end
