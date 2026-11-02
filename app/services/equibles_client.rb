require "bigdecimal"
require "json"
require "net/http"

class EquiblesClient
  BASE_URL = "https://api.equibles.com/v1".freeze
  REQUEST_TIMEOUT = 5

  def initialize(api_key:)
    @api_key = api_key.to_s.strip
  end

  def lookup(ticker_symbol)
    ticker = ticker_symbol.to_s.strip.upcase.tr(".", "-")
    return nil unless ticker.match?(/\A[A-Z0-9][A-Z0-9-]{0,31}\z/)
    return nil if @api_key.empty? || @api_key.match?(/\s/)

    quote = get("/stocks/#{ticker}/quote")
    return nil unless quote && quote["ticker"].is_a?(String) &&
                      quote["ticker"].upcase.tr(".", "-") == ticker
    return nil unless quote["stale"] == false && quote["currency"] == "USD"
    return nil unless quote["price"].is_a?(Numeric)

    price = BigDecimal(quote["price"].to_s)
    return nil unless price.finite? && price.positive?

    profile = get("/screener/stocks", tickers: ticker, limit: 1)
    return nil unless profile && profile["data"].is_a?(Array) && profile["data"].length == 1

    company = profile["data"].first
    return nil unless company.is_a?(Hash) && company["name"].is_a?(String) &&
                      !company["name"].strip.empty?

    { ticker: ticker, name: company["name"].strip, last_price: price }
  rescue JSON::ParserError, IOError, SystemCallError, SocketError, Timeout::Error,
         OpenSSL::SSL::SSLError, Net::HTTPBadResponse, Net::ProtocolError
    nil
  end

  private

  def get(path, parameters = {})
    uri = URI("#{BASE_URL}#{path}")
    uri.query = URI.encode_www_form(parameters) unless parameters.empty?
    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{@api_key}"
    request["Accept"] = "application/json"

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                              open_timeout: REQUEST_TIMEOUT, read_timeout: REQUEST_TIMEOUT,
                              max_retries: 0) do |http|
      http.request(request)
    end
    return nil unless response.is_a?(Net::HTTPSuccess)

    body = response.body
    return nil unless body.is_a?(String)

    payload = JSON.parse(body, decimal_class: BigDecimal)
    payload if payload.is_a?(Hash)
  end
end