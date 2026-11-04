class EquiblesEvidenceRefresh
  COOLDOWN = 60.seconds
  ERRORS = %w[rights_unverified encryption_unavailable missing_credentials duplicate_refresh local_quota
              invalid_instrument provider_unavailable identity_mismatch unsupported_currency invalid_price
              stale_quote invalid_delay invalid_source_time invalid_session malformed_response
              transport_failure provider_quota provider_authentication].freeze

  def initialize(connection, entitlement: nil, client_factory: nil)
    @connection = connection
    @entitlement = entitlement || EquiblesEntitlement.new(connection.user)
    @client_factory = client_factory || ->(key) { EquiblesClient.new(api_key: key) }
  end

  def call(ticker)
    # Lock spans the bounded read so key change/disconnect cannot be undone by
    # an in-flight response. One conservative quota reservation, no read retries.
    @connection.with_lock do
      now = Time.current
      @connection.expire_evidence!(@entitlement, now: now)
      next fail_with("rights_unverified") unless @entitlement.approved?
      next fail_with("encryption_unavailable") unless EquiblesConnection.encryption_configured?
      next fail_with("missing_credentials") if @connection.api_key.blank?
      unless ticker.is_a?(String) && ticker.strip.upcase.tr(".", "-").match?(/\A[A-Z0-9][A-Z0-9-]{0,31}\z/)
        next fail_with("invalid_instrument")
      end
      next fail_with("duplicate_refresh") if @connection.last_attempt_at && @connection.last_attempt_at > now - COOLDOWN

      if @connection.quota_date != now.utc.to_date
        @connection.quota_date = now.utc.to_date
        @connection.requests_used = 0
      end
      next fail_with("local_quota") if @connection.requests_used >= @entitlement.settings["daily_request_budget"]

      @connection.update!(last_attempt_at: now, requests_used: @connection.requests_used + 1,
                          quota_date: now.utc.to_date)
      begin
        snapshot = @client_factory.call(@connection.api_key).snapshot(ticker)
        snapshot["entitlement"] = @entitlement.metadata
        @connection.update!(snapshot: snapshot, last_success_at: Time.current, last_error: nil)
        true
      rescue EquiblesClient::EvidenceError => error
        fail_with(ERRORS.include?(error.message) ? error.message : "provider_unavailable")
      end
    end
  end

  private

  def fail_with(code)
    @connection.update!(last_error: code)
    Rails.logger.warn("equibles_evidence refresh_failed user_id=#{@connection.user_id} code=#{code}")
    false
  end
end
