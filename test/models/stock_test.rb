require "test_helper"
require "minitest/mock"

class StockTest < ActiveSupport::TestCase
  test "global environment and Rails credentials cannot authorize shared lookup" do
    with_api_key("eq_environment_key") do
      Rails.application.stub(:credentials, { equibles: { api_key: "eq_credentials_key" } }) do
        without_provider_calls do
          assert_nil Stock.new_lookup("AAPL")
          assert_nil Stock.new_lookup("AAPL", user: users(:one))
        end
      end
    end
  end

  test "approved cached private evidence permits only an unsaved normalized identifier" do
    with_private_evidence do |connection|
      without_provider_calls do
        stock = Stock.new_lookup(" brk.b ", user: users(:one))
        assert_equal "BRK-B", stock.ticker
        assert_equal "BRK-B", stock.name
        assert_nil stock.last_price
        assert stock.new_record?
        assert_difference "Stock.count", 1 do
          stock.save!
        end
        assert_nil stock.reload.last_price
        assert_equal "450.1234", connection.reload.snapshot["price"]
      end
    end
  end

  test "an approved user cannot reuse another user's evidence" do
    with_private_evidence do |connection|
      without_provider_calls do
        assert_no_difference "Stock.count" do
          assert_nil Stock.new_lookup("BRK-B", user: users(:two))
        end
        assert_equal "450.1234", connection.reload.snapshot["price"]
      end
    end
  end

  test "lookup rejects missing encryption without using global credentials" do
    EquiblesConnection.stub(:encryption_configured?, false) do
      without_provider_calls { assert_nil Stock.new_lookup("AAPL", user: users(:one)) }
    end
  end

  test "missing credentials and unmatched evidence cannot create shared stocks" do
    with_private_evidence do |connection|
      without_provider_calls do
        assert_nil Stock.new_lookup("AAPL", user: users(:one))
        assert_nil Stock.new_lookup("../BRK-B", user: users(:one))
        connection.update!(api_key: nil)
        assert_nil Stock.new_lookup("BRK-B", user: users(:one))
      end
    end
  end

  test "expired evidence is purged instead of used for shared lookup" do
    with_private_evidence do |connection|
      connection.update!(last_success_at: 2.hours.ago)
      without_provider_calls do
        assert_no_difference "Stock.count" do
          assert_nil Stock.new_lookup("BRK-B", user: users(:one))
        end
        assert_empty connection.reload.snapshot
      end
    end
  end

  test "database lookup matches legacy lowercase and dotted tickers" do
    stock = Stock.create!(ticker: "brk.b", name: "Berkshire Hathaway", last_price: 450)
    assert_equal stock, Stock.check_db(" BRK-B ")
  end

  test "database lookup handles blank and unknown symbols without a provider request" do
    Stock.stub(:new_lookup, ->(*) { flunk "Database lookup must not call a provider" }) do
      [nil, "", "   ", "UNKNOWN"].each { |ticker| assert_nil Stock.check_db(ticker) }
    end
  end

  test "stock requires a ticker and name" do
    stock = Stock.new
    assert_not stock.valid?
    assert_includes stock.errors[:ticker], "can't be blank"
    assert_includes stock.errors[:name], "can't be blank"
  end

  private

  def without_provider_calls(&block)
    no_provider = ->(*) { flunk "Shared stock lookup must not invoke a provider" }
    EquiblesClient.stub(:new, no_provider) do
      Net::HTTP.stub(:start, no_provider, &block)
    end
  end

  def with_private_evidence
    settings = EquiblesEntitlement::REQUIRED.index_with { true }.merge(
      "approval_reference" => "test-only-stock-identity", "daily_request_budget" => 2,
      "retention_seconds" => 3600, "freshness_seconds" => 900
    )
    configuration = { "verified_users" => users(:one, :two).to_h { |user| [user.id.to_s, settings] } }
    entitlements = users(:one, :two).to_h do |user|
      [user.id, EquiblesEntitlement.new(user, configuration: configuration)]
    end
    provider = ActiveRecord::Encryption::KeyProvider.new(
      ActiveRecord::Encryption::Key.new("s" * 32)
    )
    ActiveRecord::Encryption.with_encryption_context(key_provider: provider) do
      connection = EquiblesConnection.create!(
        user: users(:one), api_key: "eq_test_personal_key", last_success_at: 1.minute.ago,
        snapshot: {
          "instrument" => "BRK-B", "price" => "450.1234",
          "entitlement" => { "retention_seconds" => 3600 }
        }
      )
      EquiblesConnection.stub(:encryption_configured?, true) do
        EquiblesEntitlement.stub(:new, ->(user) { entitlements.fetch(user.id) }) { yield connection }
      end
    end
  end

  def with_api_key(key)
    previous_key = ENV["EQUIBLES_API_KEY"]
    key ? ENV["EQUIBLES_API_KEY"] = key : ENV.delete("EQUIBLES_API_KEY")
    yield
  ensure
    previous_key ? ENV["EQUIBLES_API_KEY"] = previous_key : ENV.delete("EQUIBLES_API_KEY")
  end
end
