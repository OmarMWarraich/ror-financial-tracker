require "test_helper"
require "minitest/mock"

class StockTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  test "lookup builds an unsaved stock from Equibles attributes" do
    with_api_key("eq_environment_key") do
      client = Minitest::Mock.new
      client.expect(:lookup, { ticker: "AAPL", name: "Apple Inc.", last_price: BigDecimal("215.3301") }, ["aapl"])
      EquiblesClient.stub(:new, ->(api_key:) { assert_equal "eq_environment_key", api_key; client }) do
        stock = Stock.new_lookup("aapl")
        assert_equal "AAPL", stock.ticker
        assert_equal "Apple Inc.", stock.name
        assert_equal BigDecimal("215.3301"), stock.last_price
        assert stock.new_record?
      end
      client.verify
    end
  end

  test "lookup returns nil when Equibles cannot supply a quote" do
    with_api_key("eq_environment_key") do
      client = Minitest::Mock.new
      client.expect(:lookup, nil, ["AAPL"])
      EquiblesClient.stub(:new, client) { assert_nil Stock.new_lookup("AAPL") }
      client.verify
    end
  end

  test "lookup falls back to encrypted Equibles credentials" do
    with_api_key(nil) do
      credentials = ActiveSupport::OrderedOptions.new
      credentials.equibles = { api_key: "eq_credentials_key" }
      client = Minitest::Mock.new
      client.expect(:lookup, nil, ["AAPL"])
      Rails.application.stub(:credentials, credentials) do
        EquiblesClient.stub(:new, ->(api_key:) { assert_equal "eq_credentials_key", api_key; client }) do
          assert_nil Stock.new_lookup("AAPL")
        end
      end
      client.verify
    end
  end

  test "database lookup matches legacy lowercase and dotted tickers" do
    stock = Stock.create!(ticker: "brk.b", name: "Berkshire Hathaway", last_price: 450)
    assert_equal stock, Stock.check_db(" BRK-B ")
  end

  private

  def with_api_key(key)
    previous_key = ENV["EQUIBLES_API_KEY"]
    key ? ENV["EQUIBLES_API_KEY"] = key : ENV.delete("EQUIBLES_API_KEY")
    yield
  ensure
    previous_key ? ENV["EQUIBLES_API_KEY"] = previous_key : ENV.delete("EQUIBLES_API_KEY")
  end
end
