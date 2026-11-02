require "test_helper"
require "minitest/mock"

class UserStocksControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  self.fixture_table_names = []

  setup do
    user = User.create!(email: "equibles-tests@example.com", password: "password123")
    sign_in user
  end

  test "unavailable quote does not create a stock or portfolio entry" do
    Stock.stub(:check_db, nil) do
      Stock.stub(:new_lookup, nil) do
        assert_no_difference ["Stock.count", "UserStock.count"] do
          post user_stocks_path, params: { ticker: "AAPL" }
        end
      end
    end

    assert_response :see_other
    assert_redirected_to my_portfolio_path
    assert_equal "Stock data is unavailable. Check the ticker or try again later.", flash[:alert]
  end

  test "invalid stock does not create a portfolio entry" do
    Stock.stub(:check_db, nil) do
      Stock.stub(:new_lookup, Stock.new(ticker: "AAPL")) do
        assert_no_difference ["Stock.count", "UserStock.count"] do
          post user_stocks_path, params: { ticker: "AAPL" }
        end
      end
    end

    assert_response :see_other
    assert_redirected_to my_portfolio_path
  end
end
