require "bigdecimal"
require "digest"
require "time"

# Offline legacy-schema checks, not a provider adapter. Never retains payloads.
class DepositInformationContract
  class Invalid < StandardError; end

  SCOPES = {
    methods: %w[add-funds query-funds].freeze,
    addresses: %w[query-funds].freeze
  }.freeze
  ADDRESS_BLOCKERS = %w[asset_identity_unverified network_identity_unverified memo_requirement_unverified].freeze

  def self.key_info!(payload, operation:, account_fingerprint:, now: Time.now)
    expected = SCOPES[operation]
    invalid! unless expected && payload.is_a?(Hash)
    scopes = payload["permissions"]
    invalid! unless scopes.is_a?(Array) && scopes.all? { |scope| scope.is_a?(String) } && scopes.sort == expected.sort
    identifier = payload["iban"]
    invalid! unless identifier.is_a?(String) && identifier.match?(/\A[A-Za-z0-9 ]{4,100}\z/)
    invalid! unless account_fingerprint.is_a?(String) && account_fingerprint.match?(/\A[0-9a-f]{64}\z/)
    invalid! unless Digest::SHA256.hexdigest(identifier) == account_fingerprint
    expiry = timestamp!(payload["valid_until"])
    invalid! if expiry.positive? && Time.at(expiry) <= now
    { permissions: scopes.dup, expires_at: expiry.zero? ? nil : Time.at(expiry) }
  end

  def self.method_evidence!(row, expected_method:)
    invalid! unless row.is_a?(Hash) && text?(expected_method) && row["method"] == expected_method
    invalid! unless decimal?(row["minimum"]) && BigDecimal(row["minimum"]).positive?
    invalid! unless row["limit"] == false || decimal?(row["limit"])
    fee_fields = %w[fee fee-percentage].select { |field| row.key?(field) }
    invalid! unless fee_fields.one? && decimal?(row[fee_fields.first])
    invalid! if row.key?("address-setup-fee") && !decimal?(row["address-setup-fee"])
    fields = ["method", "minimum", "limit", fee_fields.first]
    fields << "address-setup-fee" if row.key?("address-setup-fee")
    row.select { |field, _value| fields.include?(field) }
  end

  def self.address_review!(row, now: Time.now)
    invalid! unless row.is_a?(Hash) && text?(row["address"])
    expiry = timestamp!(row["expiretm"])
    invalid! if expiry.positive? && Time.at(expiry) <= now
    invalid! if row.key?("tag") && !text?(row["tag"])
    invalid! if row.key?("new") && ![true, false].include?(row["new"])
    # `memo` occurs in the example but not the published address schema.
    invalid! if row.key?("memo")
    # A tag's presence cannot establish that its absence is safe for another
    # asset/network. Extra client-supplied identity fields are not evidence.
    { actionable: false, blockers: ADDRESS_BLOCKERS }
  end

  def self.timestamp!(value)
    invalid! unless value.is_a?(String) && value.match?(/\A\d{1,12}\z/)
    value.to_i
  end
  private_class_method :timestamp!

  def self.decimal?(value)
    value.is_a?(String) && value.bytesize <= 100 && value.match?(/\A\d+(?:\.\d+)?\z/) && BigDecimal(value).finite?
  end
  private_class_method :decimal?

  def self.text?(value)
    value.is_a?(String) && value.bytesize.between?(1, 256) && value.match?(/\A[[:graph:] ]+\z/) && !value.strip.empty?
  end
  private_class_method :text?

  def self.invalid!
    raise Invalid, "Deposit information is incomplete, unverified, expired or outside the exact approved scope."
  end
  private_class_method :invalid!
end
