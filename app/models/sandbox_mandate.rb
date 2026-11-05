class SandboxMandate < ApplicationRecord
  belongs_to :sandbox_account
  has_many :sandbox_orders

  BOUNDS = %i[capital_limit max_notional max_quantity max_exposure loss_limit].freeze
  TERMS = (BOUNDS + %i[sandbox_account_id rule_version instrument environment session order_type expires_at]).freeze
  attr_readonly(*TERMS)

  validates :state, inclusion: { in: %w[draft active paused revoked] }
  validates :rule_version, inclusion: { in: ["trend-v1"] }
  validates :instrument, inclusion: { in: ["SYNTH-ALPHA"] }
  validates :environment, inclusion: { in: ["synthetic"] }
  validates :session, inclusion: { in: ["fixture"] }
  validates :order_type, inclusion: { in: ["synthetic_market"] }
  validates :capital_limit, numericality: { greater_than: 0, less_than_or_equal_to: 10_000 }
  validates :max_notional, :max_exposure, :loss_limit,
            numericality: { greater_than: 0, less_than_or_equal_to: 10_000 }
  validates :max_quantity, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 100 }
  validates :expires_at, presence: true
  validate :bounded_expiry, on: :create
  validate :terms_unchanged, on: :update
  validate :limits_within_capital

  def expired?
    expires_at <= Time.current
  end

  private

  def limits_within_capital
    return unless capital_limit

    %i[max_notional max_exposure loss_limit].each do |field|
      value = public_send(field)
      errors.add(field, "must not exceed approved capital") if value && value > capital_limit
    end
  end

  def bounded_expiry
    if expires_at && !(Time.current < expires_at && expires_at <= 24.hours.from_now)
      errors.add(:expires_at, "must be in the next 24 hours")
    end
  end

  def terms_unchanged
    errors.add(:base, "Terms are immutable; create a new draft and approve it") if TERMS.any? { |key| will_save_change_to_attribute?(key) }
  end
end
