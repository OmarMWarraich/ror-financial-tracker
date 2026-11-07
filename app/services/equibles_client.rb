require "bigdecimal"
require "json"
require "net/http"
require "time"
require "date"

class EquiblesClient
  BASE_URL = "https://api.equibles.com/v1".freeze
  REQUEST_TIMEOUT = 5
  class EvidenceError < StandardError; end

  def initialize(api_key:, on_headers: nil, on_request: nil)
    @api_key = api_key.to_s.strip
    @on_headers = on_headers
    @on_request = on_request
  end

  def profiles(tickers)
    unless tickers.is_a?(Array) && tickers.length.between?(1, 3) &&
           tickers.all? { |ticker| ticker.is_a?(String) && ticker.match?(/\A[A-Z][A-Z0-9-]{0,19}\z/) }
      raise EvidenceError, "invalid_instrument"
    end
    data = data!("/screener/stocks", tickers: tickers.join(","), limit: tickers.length)
    rows = data["data"]
    raise EvidenceError, "malformed_response" unless rows.is_a?(Array) && rows.length <= tickers.length
    rows.each_with_object({}) do |row, result|
      unless row.is_a?(Hash) && row["ticker"].is_a?(String) && row["name"].is_a?(String) &&
             row["name"].length.between?(1, 200) &&
             (row["sector"].nil? || (row["sector"].is_a?(String) && row["sector"].length <= 200))
        raise EvidenceError, "malformed_response"
      end
      ticker = row["ticker"].upcase.tr(".", "-")
      next unless tickers.include?(ticker)
      raise EvidenceError, "identity_mismatch" if result.key?(ticker)
      result[ticker] = row.slice("name", "sector")
    end
  end

  def earnings(ticker)
    raise EvidenceError, "invalid_instrument" unless ticker.is_a?(String) && ticker.match?(/\A[A-Z][A-Z0-9-]{0,19}\z/)
    data = data!("/stocks/#{ticker}/financial-facts/eps-diluted")
    raise EvidenceError, "identity_mismatch" unless data["ticker"].is_a?(String) && data["ticker"].upcase.tr(".", "-") == ticker
    concept = data["concept"].to_s.downcase.gsub(/[^a-z]/, "")
    unless %w[epsdiluted earningspersharediluted usgaapearningspersharediluted].include?(concept)
      raise EvidenceError, "unexpected_earnings_concept"
    end
    rows = data["quarterly"]
    raise EvidenceError, "malformed_response" unless rows.nil? || (rows.is_a?(Array) && rows.length <= 500)
    if rows && !rows.empty? && !%w[USD/shares USD/share USD/sh].include?(data["unit"])
      raise EvidenceError, "unsupported_currency"
    end
    points = Array(rows).map do |row|
      unless row.is_a?(Hash) && row["value"].is_a?(Numeric) && BigDecimal(row["value"].to_s).finite? &&
             [nil, "today", "as-filed"].include?(row["splitBasis"]) &&
             (row["fiscalPeriod"].nil? || (row["fiscalPeriod"].is_a?(String) && row["fiscalPeriod"].length <= 40))
        raise EvidenceError, "malformed_response"
      end
      ending = Date.iso8601(row.fetch("periodEnd"))
      filed = Date.iso8601(row.fetch("filedDate"))
      unless ending.iso8601 == row["periodEnd"] && filed.iso8601 == row["filedDate"] &&
             ending <= filed && filed <= Time.now.utc.to_date
        raise EvidenceError, "invalid_source_time"
      end
      row.slice("fiscalPeriod", "value", "periodEnd", "filedDate", "splitBasis")
    end
    { "points" => points.sort_by { |row| [row.fetch("periodEnd"), row.fetch("filedDate")] }.last(4).reverse,
      "unit" => data["unit"], "coverage_note" => data["coverageNote"].to_s[0, 500],
      "company_name" => data["companyName"].is_a?(String) ? data["companyName"][0, 200] : nil }
  rescue KeyError, ArgumentError, TypeError
    raise EvidenceError, "malformed_response"
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

  # Contract: https://api.equibles.com/openapi/v1.json (LiveQuoteDto).
  # No issuer-profile request is needed for evidence of the exact quote identity.
  def snapshot(ticker_symbol, received_at: nil)
    ticker = ticker_symbol.to_s.strip.upcase.tr(".", "-")
    raise EvidenceError, "invalid_instrument" unless ticker.match?(/\A[A-Z0-9][A-Z0-9-]{0,31}\z/)
    raise EvidenceError, "missing_credentials" if @api_key.empty? || @api_key.match?(/\s/)

    @last_status = nil
    quote = get("/stocks/#{ticker}/quote")
    received_at ||= Time.now.utc
    raise EvidenceError, "provider_quota" if @last_status == "429"
    raise EvidenceError, "provider_authentication" if %w[401 403].include?(@last_status)
    raise EvidenceError, "provider_unavailable" unless quote
    unless quote["ticker"].is_a?(String) && quote["ticker"].upcase.tr(".", "-") == ticker
      raise EvidenceError, "identity_mismatch"
    end
    raise EvidenceError, "unsupported_currency" unless quote["currency"] == "USD"
    raise EvidenceError, "invalid_price" unless quote["price"].is_a?(Numeric)
    price = BigDecimal(quote["price"].to_s)
    raise EvidenceError, "invalid_price" unless price.finite? && price.positive?
    raise EvidenceError, "stale_quote" unless quote["stale"] == false
    raise EvidenceError, "invalid_delay" unless [true, false, nil].include?(quote["delayed"])

    if quote["asOf"] && (!quote["asOf"].is_a?(String) ||
                         !quote["asOf"].match?(/T.*(?:Z|[+-]\d{2}:\d{2})\z/))
      raise EvidenceError, "invalid_source_time"
    end
    source_at = quote["asOf"].nil? ? nil : Time.iso8601(quote["asOf"]).utc
    raise EvidenceError, "invalid_source_time" if source_at && source_at > received_at
    sessions = %w[sessionDate expectedSessionDate].to_h do |field|
      value = quote[field]
      if value && (!value.is_a?(String) || !value.match?(/\A\d{4}-\d{2}-\d{2}\z/) ||
                   Date.iso8601(value).iso8601 != value)
        raise EvidenceError, "invalid_session"
      end
      [field, value]
    end
    {
      "provider" => "equibles", "instrument" => ticker, "product_type" => "listed_security",
      "currency" => "USD", "price" => price.to_s("F"),
      "source_at" => source_at&.iso8601(6), "received_at" => received_at.utc.iso8601(6),
      "session" => sessions, "observation_type" => "latest_intraday_quote",
      "delayed" => quote["delayed"], "stale" => false,
      "quality" => source_at ? (quote["delayed"] == true ? "delayed" : "timing_unverified") : "unknown_source_time",
      "decision_eligible" => false
    }
  rescue JSON::ParserError
    raise EvidenceError, "malformed_response"
  rescue ArgumentError, TypeError
    raise EvidenceError, "malformed_response"
  rescue IOError, SystemCallError, SocketError, Timeout::Error,
         OpenSSL::SSL::SSLError, Net::HTTPBadResponse, Net::ProtocolError
    raise EvidenceError, "transport_failure"
  end

  private

  def data!(path, parameters = {})
    raise EvidenceError, "missing_credentials" if @api_key.empty? || @api_key.match?(/\s/)
    payload = get(path, parameters)
    raise EvidenceError, "provider_quota" if @last_status == "429"
    raise EvidenceError, "provider_authentication" if %w[401 403].include?(@last_status)
    raise EvidenceError, "provider_not_found" if @last_status == "404"
    raise EvidenceError, "provider_unavailable" unless payload
    payload
  rescue JSON::ParserError
    raise EvidenceError, "malformed_response"
  rescue IOError, SystemCallError, SocketError, Timeout::Error,
         OpenSSL::SSL::SSLError, Net::HTTPBadResponse, Net::ProtocolError
    raise EvidenceError, "transport_failure"
  end

  def get(path, parameters = {})
    @last_status = nil
    uri = URI("#{BASE_URL}#{path}")
    uri.query = URI.encode_www_form(parameters) unless parameters.empty?
    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{@api_key}"
    request["Accept"] = "application/json"

    @on_request&.call
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                              open_timeout: REQUEST_TIMEOUT, read_timeout: REQUEST_TIMEOUT,
                              max_retries: 0) do |http|
      http.request(request)
    end
    @on_headers&.call(response.code.to_i, response.each_header.to_h)
    unless response.is_a?(Net::HTTPSuccess)
      @last_status = response.code
      return nil
    end

    body = response.body
    return nil unless body.is_a?(String) && body.bytesize <= 1_048_576

    payload = JSON.parse(body, decimal_class: BigDecimal)
    payload if payload.is_a?(Hash)
  end
end