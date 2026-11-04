require "test_helper"

class UserStockTest < ActiveSupport::TestCase
  test "watchlist entry requires an existing owner and stock" do
    entry = UserStock.new
    assert_not entry.valid?
    assert_includes entry.errors[:user], "must exist"
    assert_includes entry.errors[:stock], "must exist"
  end

  test "watchlists share stock data without sharing ownership" do
    assert_equal [stocks(:one)], users(:one).stocks.to_a
    assert_equal [stocks(:two)], users(:two).stocks.to_a
    assert_equal users(:one), user_stocks(:one).user
  end
end
