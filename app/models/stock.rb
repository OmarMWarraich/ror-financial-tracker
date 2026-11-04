class Stock < ApplicationRecord
  has_many :user_stocks
  has_many :users, through: :user_stocks

  validates :name, :ticker, presence: true

  def self.new_lookup(ticker_symbol, user: nil)
    return nil unless user && EquiblesConnection.encryption_configured?

    ticker = ticker_symbol.to_s.strip.upcase.tr(".", "-")
    return nil unless ticker.match?(/\A[A-Z0-9][A-Z0-9-]{0,31}\z/)

    entitlement = EquiblesEntitlement.new(user)
    return nil unless entitlement.approved?
    connection = EquiblesConnection.find_by(user_id: user.id)
    return nil unless connection

    connection.with_lock do
      connection.expire_evidence!(entitlement)
      next nil if connection.api_key.blank? || connection.snapshot["instrument"] != ticker

      # Stocks are socially shared. Only the user's requested public identifier
      # may enter that table; licensed quote evidence stays private to its owner.
      # Searches never spend quota: retrieve evidence explicitly through POST.
      new(ticker: ticker, name: ticker, last_price: nil)
    end
  rescue ActiveRecord::Encryption::Errors::Base
    nil
  end

  def self.check_db(ticker_symbol)
    ticker = ticker_symbol.to_s.strip.upcase.tr(".", "-")
    where("UPPER(REPLACE(ticker, '.', '-')) = ?", ticker).first
  end
end
