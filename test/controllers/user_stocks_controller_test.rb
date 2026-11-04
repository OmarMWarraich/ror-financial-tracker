require "test_helper"
require "minitest/mock"

class UserStocksControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:one)
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

  test "cached normalized ticker adds only to the authenticated user's watchlist" do
    Stock.stub(:new_lookup, ->(*) { flunk "Cached stocks must not query a provider" }) do
      assert_no_difference "Stock.count" do
        assert_difference "users(:one).user_stocks.count", 1 do
          assert_no_difference "users(:two).user_stocks.count" do
            post user_stocks_path, params: { ticker: " msft ", user_id: users(:two).id }
          end
        end
      end
    end
    assert_redirected_to my_portfolio_path
    assert users(:one).stocks.exists?(stocks(:two).id)
  end

  test "duplicate tracking is rejected even when posting directly" do
    assert_no_difference "UserStock.count" do
      post user_stocks_path, params: { ticker: " aapl " }
    end
    assert_response :see_other
    assert_redirected_to my_portfolio_path
  end

  test "ten stock limit is enforced before looking up or persisting a stock" do
    9.times do |index|
      users(:one).stocks.create!(ticker: "LIMIT#{index}", name: "Limit #{index}", last_price: 1)
    end
    Stock.stub(:new_lookup, ->(*) { flunk "Full watchlists must not query a provider" }) do
      assert_no_difference ["Stock.count", "UserStock.count"] do
        post user_stocks_path, params: { ticker: "UNTRACKED" }
      end
    end
    assert_response :see_other
    assert_redirected_to my_portfolio_path
  end

  test "removal deletes only the current user's link and preserves shared stock" do
    users(:two).stocks << stocks(:one)
    assert_no_difference ["Stock.count", "users(:two).user_stocks.count"] do
      assert_difference "users(:one).user_stocks.count", -1 do
        delete user_stock_path(stocks(:one)), params: { user_id: users(:two).id }
      end
    end
    assert_redirected_to my_portfolio_path
    assert Stock.exists?(stocks(:one).id)
  end

  test "another user's untracked stock cannot be removed" do
    assert_no_difference ["Stock.count", "UserStock.count"] do
      delete user_stock_path(stocks(:two))
    end
    assert_response :not_found
    assert UserStock.exists?(user_stocks(:two).id)
  end

  test "signed out users cannot add or remove portfolio entries" do
    sign_out users(:one)
    Stock.stub(:new_lookup, ->(*) { flunk "Signed out users must not query a provider" }) do
      assert_no_difference ["Stock.count", "UserStock.count"] do
        post user_stocks_path, params: { ticker: "UNTRACKED" }
        assert_redirected_to new_user_session_path
        delete user_stock_path(stocks(:one))
        assert_redirected_to new_user_session_path
      end
    end

  end

  test "Hotwire add and remove render watchlist stream updates" do
    assert_difference "UserStock.count", 1 do
      post user_stocks_path, params: { ticker: "MSFT" }, as: :turbo_stream
    end
    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_select "turbo-stream[target='stocks-list']"
    assert_includes response.body, "Microsoft Corporation"

    assert_difference "UserStock.count", -1 do
      delete user_stock_path(stocks(:two)), as: :turbo_stream
    end
    assert_response :success
    assert_select "turbo-stream[action='replace'][target='stocks-list']"
    assert_not_includes response.body, "Microsoft Corporation"
  end
end
