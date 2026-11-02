class Stock < ApplicationRecord
  has_many :user_stocks
  has_many :users, through: :user_stocks

  validates :name, :ticker, presence: true

  def self.new_lookup(ticker_symbol)
    api_key = ENV["EQUIBLES_API_KEY"].presence || Rails.application.credentials.dig(:equibles, :api_key)
    attributes = EquiblesClient.new(api_key: api_key).lookup(ticker_symbol)
    new(attributes) if attributes
  end

  def self.check_db(ticker_symbol)
    ticker = ticker_symbol.to_s.strip.upcase.tr(".", "-")
    where("UPPER(REPLACE(ticker, '.', '-')) = ?", ticker).first
  end
end
