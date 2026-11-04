require "digest"

class BrokerConnection < ApplicationRecord
  belongs_to :user
  encrypts :api_key, :api_secret, :account_identifier, :balance_payload, :history_payload
  attr_readonly :user_id, :product, :mode, :key_fingerprint, :include_history

  STATES = %w[pending verified blocked disconnected expired revoked].freeze
  validates :label, presence: true, length: { maximum: 80 }
  validates :product, inclusion: { in: ["exchange"] }
  validates :mode, inclusion: { in: ["read_only"] }
  validates :state, inclusion: { in: STATES }
  validates :elevation_state, inclusion: { in: %w[not_requested requested] }
  validates :key_fingerprint, presence: true, uniqueness: true
  validates :expires_at, presence: true
  validates :api_key, :api_secret, presence: true, if: :credentials_required?
  validates :api_key, length: { maximum: 256 }, allow_nil: true
  validates :api_secret, length: { maximum: 512 }, allow_nil: true
  validate :bounded_expiry, on: :create
  before_validation :fingerprint_key, on: :create

  def self.encryption_ready?
    %w[ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY
       ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT].all? { |name| ENV[name].present? }
  end

  def active?
    %w[pending verified].include?(state) && expires_at > Time.current
  end

  def stale?
    state != "verified" || last_error.present? || received_at.nil? || received_at < 5.minutes.ago
  end

  def balances
    balance_payload.present? ? JSON.parse(balance_payload) : nil
  end

  def history
    history_payload.present? ? JSON.parse(history_payload) : nil
  end

  def disconnect!
    with_lock do
      update!(state: "disconnected", disconnected_at: Time.current,
              api_key: nil, api_secret: nil, account_identifier: nil,
              balance_payload: nil, history_payload: nil, verified_permissions: [],
              elevation_state: "not_requested", elevation_requested_at: nil)
    end
  end

  def request_elevation!
    with_lock do
      raise KrakenReadOnlyClient::Error, "Verify an active read-only connection first." unless active? && state == "verified"

      update!(elevation_state: "requested", elevation_requested_at: Time.current)
    end
  end

  private

  def credentials_required?
    %w[pending verified].include?(state)
  end

  def fingerprint_key
    self.key_fingerprint = Digest::SHA256.hexdigest(api_key) if api_key.present?
  end

  def bounded_expiry
    return if expires_at.nil?
    errors.add(:expires_at, "must be in the next 90 days") unless expires_at > Time.current && expires_at <= 90.days.from_now
  end
end
