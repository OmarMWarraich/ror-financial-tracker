require "base64"
require "bigdecimal"
require "json"
require "net/http"
require "openssl"
require "time"

class KrakenReadOnlyClient
  class Error < StandardError; end
  class PermissionError < Error; end
  class RevokedError < Error; end

  HOST = "api.kraken.com".freeze
  PATHS = {
    key_info: "/0/private/GetApiKeyInfo",
    balances: "/0/private/Balance",
    trades: "/0/private/TradesHistory"
  }.freeze

  def initialize(api_key:, api_secret:, nonce:)
    @api_key = api_key
    @api_secret = api_secret
    @nonce = nonce
    raise Error, "Invalid Kraken API key format." unless api_key.is_a?(String) && api_key.match?(/\A[A-Za-z0-9+\/=]{8,256}\z/)
    raise Error, "Invalid Kraken API secret format." unless api_secret.is_a?(String) && Base64.strict_decode64(api_secret).bytesize >= 32
  rescue ArgumentError
    raise Error, "Invalid Kraken API secret format."
  end

  def key_info(include_history:)
    result = request(:key_info)
    required = ["query-funds"]
    required << "query-closed-trades" if include_history
    permissions = result["permissions"]
    unless permissions.is_a?(Array) && permissions.all? { |item| item.is_a?(String) } &&
           permissions.sort == required.sort
      raise PermissionError, "Use a dedicated key with only the permissions required by this screen. Unverifiable or additional scopes block syncing."
    end

    # The published schema and example use different casing; accept only these documented forms.
    identifier = result["iban"]
    expiry = result["valid_until"] || result["validUntil"]
    unless identifier.is_a?(String) && identifier.match?(/\A[A-Za-z0-9 ]{4,100}\z/) &&
           expiry.is_a?(String) && expiry.match?(/\A\d+\z/)
      raise PermissionError, "Kraken key account identity or expiry could not be verified."
    end
    raise RevokedError, "The Kraken key has expired." if expiry.to_i.positive? && Time.at(expiry.to_i) <= Time.now

    { identifier: identifier, permissions: permissions,
      expires_at: expiry.to_i.positive? ? Time.at(expiry.to_i) : nil }
  end

  def balances
    request(:balances).map do |asset_id, quantity|
      unless asset_id.is_a?(String) && asset_id.match?(/\A[A-Za-z0-9._-]{1,40}\z/) && decimal?(quantity)
        raise Error, "Kraken returned malformed balance evidence."
      end

      { "provider_instrument_id" => asset_id, "quantity" => BigDecimal(quantity).to_s("F"),
        "product_type" => "unclassified_exchange_asset", "analytics_supported" => false }
    end
  end

  def trades
    result = request(:trades, "ofs" => 0)
    trades = result["trades"]
    raise Error, "Kraken returned malformed trade history." unless trades.is_a?(Hash) && trades.size <= 50

    trades.map do |_id, trade|
      unless trade.is_a?(Hash) && trade["pair"].is_a?(String) &&
             trade["pair"].match?(/\A[A-Za-z0-9._\/-]{1,80}\z/) &&
             %w[buy sell].include?(trade["type"]) && %w[price vol cost fee].all? { |field| decimal?(trade[field]) } &&
             trade["time"].is_a?(Numeric) && trade["time"].finite? && trade["time"].positive?
        raise Error, "Kraken returned malformed trade history."
      end
      { "provider_instrument_id" => trade["pair"], "product_type" => "unclassified_exchange_pair",
        "side" => trade["type"], "quantity" => BigDecimal(trade["vol"]).to_s("F"),
        "price" => BigDecimal(trade["price"]).to_s("F"), "cost" => BigDecimal(trade["cost"]).to_s("F"),
        "fee" => BigDecimal(trade["fee"]).to_s("F"),
        "source_time" => Time.at(trade["time"]).utc.iso8601, "analytics_supported" => false }
    end
  end

  private

  def decimal?(value)
    value.is_a?(String) && value.match?(/\A\d+(?:\.\d+)?\z/) && BigDecimal(value).finite?
  end

  def request(operation, parameters = {})
    path = PATHS.fetch(operation)
    nonce = @nonce.call.to_s
    body = URI.encode_www_form({ "nonce" => nonce }.merge(parameters))
    digest = OpenSSL::Digest::SHA256.digest(nonce + body)
    signature = Base64.strict_encode64(
      OpenSSL::HMAC.digest("SHA512", Base64.strict_decode64(@api_secret), path + digest)
    )
    http_request = Net::HTTP::Post.new(path)
    http_request["API-Key"] = @api_key
    http_request["API-Sign"] = signature
    http_request["Content-Type"] = "application/x-www-form-urlencoded"
    http_request["Accept"] = "application/json"
    http_request.body = body
    response = Net::HTTP.start(HOST, 443, use_ssl: true, open_timeout: 5, read_timeout: 5,
                              write_timeout: 5, max_retries: 0) { |http| http.request(http_request) }
    raise Error, "Kraken rate limit reached. Wait before refreshing." if response.code == "429"
    raise Error, "Kraken request failed; retained evidence has not been refreshed." unless response.is_a?(Net::HTTPSuccess)
    raise Error, "Kraken returned an oversized response." unless response.body.is_a?(String) && response.body.bytesize <= 1_000_000

    payload = JSON.parse(response.body)
    unless payload.is_a?(Hash) && payload["error"].is_a?(Array) && payload["error"].all? { |error| error.is_a?(String) }
      raise Error, "Kraken returned a malformed response."
    end
    unless payload["error"].empty?
      if payload["error"].any? { |error| error.start_with?("EAPI:Invalid key", "EGeneral:Permission denied") }
        raise RevokedError, "Kraken rejected this key or its permissions. Create a new dedicated key."
      end
      raise Error, "Kraken rejected the read request. Check key status, nonce configuration, and rate limits."
    end
    raise Error, "Kraken returned missing evidence." unless payload["result"].is_a?(Hash)

    payload["result"]
  rescue JSON::ParserError
    raise Error, "Kraken returned invalid JSON."
  rescue IOError, SystemCallError, SocketError, Timeout::Error, OpenSSL::SSL::SSLError,
         Net::HTTPBadResponse, Net::ProtocolError
    raise Error, "Kraken is unavailable. Retained evidence has not been refreshed."
  end
end
