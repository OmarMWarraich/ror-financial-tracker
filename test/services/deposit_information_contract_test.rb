require "minitest/autorun"
require "minitest/mock"
require "net/http"
require_relative "../../app/services/deposit_information_contract"
require_relative "../../app/services/deposit_information_policy"
require_relative "../../app/models/deposit_information_capability"

class DepositInformationContractTest < Minitest::Test
  def setup
    @now = Time.utc(2026, 11, 5)
    @account = "AA88 FAKE ACCOUNT"
    @fingerprint = Digest::SHA256.hexdigest(@account)
    @info = { "permissions" => %w[query-funds add-funds], "iban" => @account, "valid_until" => "0" }
    @method = { "method" => "Bitcoin", "minimum" => "0.0001", "limit" => false, "fee" => "0.0000" }
    @user = Struct.new(:id).new(123)
    @review = { "reference" => "offline-test-only", "expires_at" => (@now + 3600).iso8601,
                "account_fingerprint" => @fingerprint, "product" => "exchange_crypto",
                "revoked" => false, "assets" => { "XBT" => ["Bitcoin"] } }
    @settings = { enabled: true, approved_users: { "123" => @review } }
  end

  def test_exact_documented_scopes_are_operation_specific_and_not_monitoring_promotion
    result = key_info(@info)
    assert_equal %w[query-funds add-funds], result[:permissions]
    refute result.key?(:iban)
    assert_nil result[:expires_at]
    assert_raises(DepositInformationContract::Invalid) { key_info(@info.merge("permissions" => ["query-funds"])) }
    assert_raises(DepositInformationContract::Invalid) { key_info(@info, operation: :addresses) }
    assert_equal ["query-funds"], key_info(@info.merge("permissions" => ["query-funds"]), operation: :addresses)[:permissions]
    %w[withdraw-funds modify-trades close-trades earn-funds query-ledger create-ws-token unknown].each do |extra|
      assert_raises(DepositInformationContract::Invalid) do
        key_info(@info.merge("permissions" => @info["permissions"] + [extra]))
      end
    end
    [nil, [], "add-funds", ["query-funds", "add-funds", "add-funds"]].each do |scopes|
      assert_raises(DepositInformationContract::Invalid) { key_info(@info.merge("permissions" => scopes)) }
    end
    assert_raises(DepositInformationContract::Invalid) { key_info(@info, operation: :withdraw) }
  end

  def test_account_binding_expiry_and_missing_metadata_fail_closed_without_payload_in_errors
    [{ "iban" => "OTHER PRIVATE ACCOUNT" }, { "iban" => nil }, { "valid_until" => nil },
     { "valid_until" => "invalid" }, { "valid_until" => @now.to_i.to_s },
     { "valid_until" => (@now.to_i - 1).to_s }].each do |change|
      error = assert_raises(DepositInformationContract::Invalid) { key_info(@info.merge(change)) }
      refute_includes error.message, "PRIVATE"
    end
    assert_raises(DepositInformationContract::Invalid) { key_info(@info.except("valid_until").merge("validUntil" => "0")) }
    assert_equal @now + 60, key_info(@info.merge("valid_until" => (@now.to_i + 60).to_s))[:expires_at]
  end

  def test_minimum_limit_and_fee_are_real_required_fields_not_defaulted_values
    assert_equal @method, DepositInformationContract.method_evidence!(@method, expected_method: "Bitcoin")
    %w[minimum limit fee].each do |missing|
      assert_raises(DepositInformationContract::Invalid) { method_evidence(@method.reject { |key, _| key == missing }) }
    end
    [{ "minimum" => "0" }, { "minimum" => 1 }, { "fee" => nil }, { "fee" => "-1" },
     { "fee" => "NaN" }, { "fee" => "Infinity" }, { "fee" => "1" * 101 },
     { "limit" => true }, { "method" => "Other network" }, { "address-setup-fee" => nil },
     { "fee-percentage" => "0.1" }].each do |change|
      assert_raises(DepositInformationContract::Invalid) { method_evidence(@method.merge(change)) }
    end
    percent = @method.reject { |key, _| key == "fee" }.merge("fee-percentage" => "0.1")
    assert_equal "0.1", method_evidence(percent)["fee-percentage"]
    refute method_evidence(percent).key?("fee")
  end

  def test_wrong_network_missing_memo_and_even_present_tag_never_make_legacy_addresses_actionable
    [nil, "fake-tag"].each do |tag|
      row = { "address" => "FAKE-DESTINATION-NOT-FOR-USE", "expiretm" => "0" }
      row["tag"] = tag if tag
      row.merge!("asset" => "XBT", "network" => "wrong-network", "memo_required" => false)
      result = DepositInformationContract.address_review!(row, now: @now)
      assert_equal false, result[:actionable]
      assert_includes result[:blockers], "network_identity_unverified"
      assert_includes result[:blockers], "asset_identity_unverified"
      assert_includes result[:blockers], "memo_requirement_unverified"
      refute_includes result.to_s, "FAKE-DESTINATION"
      refute_includes result.to_s, "fake-tag"
    end
    [{ "tag" => "" }, { "memo" => "schema-does-not-define-this-field" }, { "expiretm" => nil },
     { "expiretm" => @now.to_i.to_s }, { "new" => "true" }, { "address" => "<script>\n" }].each do |change|
      assert_raises(DepositInformationContract::Invalid) do
        DepositInformationContract.address_review!({ "address" => "FAKE", "expiretm" => "0" }.merge(change), now: @now)
      end
    end
  end

  def test_operator_review_is_owner_account_asset_network_expiry_and_revocation_bound
    assert approved?
    symbolized = { enabled: true, approved_users: {
      :"123" => @review.transform_keys(&:to_sym).merge(assets: { XBT: ["Bitcoin"] })
    } }
    assert approved?(@user, settings: symbolized)
    refute approved?(Struct.new(:id).new(999))
    refute approved?(@user, account_identifier: "OTHER FAKE ACCOUNT")
    refute approved?(@user, asset: "USD")
    refute approved?(@user, network: "Lightning")
    refute approved?(@user, settings: { enabled: false, approved_users: @settings[:approved_users] })
    refute approved?(@user, settings: { enabled: true, approved_users: {} })
    refute approved?(@user, settings: { enabled: true, approved_users: nil })
    [{ "revoked" => true }, { "revoked" => nil }, { "product" => "securities" },
     { "reference" => "" }, { "expires_at" => @now.iso8601 }, { "expires_at" => "bad" },
     { "assets" => nil }, { "account_fingerprint" => nil }].each do |change|
      settings = { enabled: true, approved_users: { "123" => @review.merge(change) } }
      refute approved?(@user, settings: settings)
    end
  end

  def test_configuration_cannot_enable_capability_and_checks_never_dispatch
    Net::HTTP.stub(:start, ->(*) { flunk "Offline validation must never contact Kraken" }) do
      assert approved?
      key_info(@info)
      method_evidence(@method)
      capability = DepositInformationCapability.new
      refute capability.available?
      assert capability.blockers.any? { |blocker| blocker.include?("encrypted credentials") }
    end
    refute DepositInformationContract.respond_to?(:request)
    refute DepositInformationContract.respond_to?(:deposit)
    refute DepositInformationContract.respond_to?(:withdraw)
    refute DepositInformationContract.respond_to?(:create_address)
  end

  private

  def key_info(payload, operation: :methods)
    DepositInformationContract.key_info!(payload, operation: operation, account_fingerprint: @fingerprint, now: @now)
  end

  def method_evidence(payload)
    DepositInformationContract.method_evidence!(payload, expected_method: "Bitcoin")
  end

  def approved?(user = @user, account_identifier: @account, asset: "XBT", network: "Bitcoin", settings: @settings)
    DepositInformationPolicy.approved?(user, account_identifier: account_identifier, asset: asset,
                                       network: network, settings: settings, now: @now)
  end
end
