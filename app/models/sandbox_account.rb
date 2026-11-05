class SandboxAccount < ApplicationRecord
  belongs_to :user
  has_many :sandbox_mandates
  has_many :sandbox_orders
  has_many :sandbox_events

  validates :user_id, uniqueness: true
  validates :environment, inclusion: { in: ["synthetic"] }
  validates :currency, inclusion: { in: ["USD"] }
  validates :initial_cash, numericality: { greater_than: 0, less_than_or_equal_to: 10_000 }
  validates :cash, :cost_basis, numericality: { greater_than_or_equal_to: 0 }
  validates :quantity, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :fixture_key, inclusion: { in: ->(_) { SandboxFixtures::DATA.keys } }
  validates :fixture_loaded_at, presence: true

  attr_readonly :user_id, :environment, :currency, :initial_cash
end
