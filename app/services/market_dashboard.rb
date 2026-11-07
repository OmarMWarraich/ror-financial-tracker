class MarketDashboard
  DEFAULT_TICKERS = %w[AAPL MSFT NVDA].freeze
  DAILY_REQUESTS = 30
  DEADLINE = 20

  def self.enabled?
    %w[development test].include?(Rails.env) && ENV["MARKET_DASHBOARD_ENABLED"] == "1"
  end

  def self.tickers(input)
    unless input.is_a?(String) && input.bytesize <= 80
      raise EquiblesClient::EvidenceError, "invalid_instrument"
    end
    values = input.split(",", -1).map { |value| value.strip.upcase.tr(".", "-") }
    unless values.length.between?(1, 3) && values.uniq == values &&
           values.all? { |value| value.match?(/\A[A-Z][A-Z0-9-]{0,19}\z/) }
      raise EquiblesClient::EvidenceError, "invalid_instrument"
    end
    values
  end

  def initialize(tickers:, api_key: ENV["EQUIBLES_API_KEY"], client_factory: nil)
    @tickers = self.class.tickers(tickers)
    @key = api_key.to_s.strip
    @digest = Digest::SHA256.hexdigest(@key)
    @requests = 0
    @errors = []
    @client_factory = client_factory || ->(key, on_request, on_headers) {
      EquiblesClient.new(api_key: key, on_request: on_request, on_headers: on_headers)
    }
  end

  def call
    raise EquiblesClient::EvidenceError, "dashboard_disabled" unless self.class.enabled?
    raise EquiblesClient::EvidenceError, "missing_credentials" if @key.empty? || @key.match?(/\s/)
    raise EquiblesClient::EvidenceError, "invalid_credentials" unless @key.match?(/\Aeq_[^\s]{1,250}\z/)
    raise EquiblesClient::EvidenceError, "database_transaction_open" if ApplicationRecord.connection.transaction_open?
    @deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + DEADLINE
    @client = @client_factory.call(@key, -> { reserve! }, ->(status, headers) { observe!(status, headers) })
    profiles = capture("Company profiles") { @client.profiles(@tickers) } || {}
    stocks = @tickers.map do |ticker|
      quote = capture("#{ticker} quote") { @client.snapshot(ticker) }
      earnings = capture("#{ticker} earnings") { @client.earnings(ticker) }
      { ticker: ticker, name: profiles.dig(ticker, "name") || earnings&.[]("company_name") || ticker,
        sector: profiles.dig(ticker, "sector"), quote: quote, earnings: earnings }
    end
    { stocks: stocks, errors: @errors, requests: @requests, received_at: Time.current.utc }
  end

  private

  def reserve!
    raise EquiblesClient::EvidenceError, @stop if @stop
    if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= @deadline
      raise EquiblesClient::EvidenceError, "dashboard_deadline"
    end
    ApplicationRecord.transaction do
      Research::SourceQuota.account_key_lock!(@digest)
      connection = EquiblesConnection.find_by(quota_key_digest: @digest)
      if connection && connection.quota_observation["date"] == Time.current.utc.to_date.iso8601
        observation = connection.quota_observation
        raise EquiblesClient::EvidenceError, "source_budget_unknown" if observation["unknown"]
        if observation["blocked"] || observation["remaining"] == 0
          raise EquiblesClient::EvidenceError, "provider_quota"
        end
      end
      used = connection ? Research::SourceQuota.group_used(connection) :
        ResearchSourceUsage.where(key_digest: @digest, budget_date: Time.current.utc.to_date).sum(:requests_used)
      held = connection ? Research::SourceQuota.held(connection) : 0
      raise EquiblesClient::EvidenceError, "local_quota" if used + held >= DAILY_REQUESTS
      ResearchSourceUsage.create!(key_digest: @digest, budget_date: Time.current.utc.to_date, requests_used: 1)
    end
    @requests += 1
  end

  def observe!(status, headers)
    @stop = "provider_authentication" if [401, 403].include?(status)
    @stop = "provider_quota" if status == 429
    remaining = headers["x-ratelimit-remaining"] || headers["ratelimit-remaining"]
    @stop = "provider_quota" if remaining.to_s.match?(/\A\d+\z/) && remaining.to_i.zero?
    EquiblesConnection.where(quota_key_digest: @digest).find_each do |connection|
      Research::SourceQuota.observe_connection!(connection, status, headers,
        settings: { "quota_header_semantics" => "utc_daily_requests_remaining" })
    end
  end

  def capture(label)
    yield
  rescue EquiblesClient::EvidenceError => error
    @stop = error.message if %w[local_quota provider_quota provider_authentication dashboard_deadline transport_failure source_budget_unknown].include?(error.message)
    @errors << "#{label}: #{error.message.humanize}."
    Rails.logger.warn("market_dashboard component=#{label} code=#{error.message}")
    nil
  end
end
