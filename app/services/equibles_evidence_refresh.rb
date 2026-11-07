class EquiblesEvidenceRefresh
  COOLDOWN = 60.seconds
  ERRORS = %w[rights_unverified encryption_unavailable missing_credentials duplicate_refresh local_quota
              invalid_instrument provider_unavailable identity_mismatch unsupported_currency invalid_price
              stale_quote invalid_delay invalid_source_time invalid_session malformed_response
              transport_failure provider_quota provider_authentication].freeze

  def initialize(connection, entitlement: nil, client_factory: nil)
    @connection = connection
    @entitlement = entitlement || EquiblesEntitlement.new(connection.user)
    @client_factory = client_factory || ->(key) {
      EquiblesClient.new(api_key: key, on_headers: ->(status, headers) {
        Research::SourceQuota.observe_connection!(@connection, status, headers,
          settings: Research::Policy.new(@connection.user).settings)
      })
    }
  end

  def call(ticker)
    reservation = @connection.with_lock do
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
      Research::SourceQuota.account_lock!(@connection)
      next fail_with("local_quota") if Research::SourceQuota.group_used(@connection) + Research::SourceQuota.held(@connection) >= @entitlement.settings["daily_request_budget"]

      @connection.update!(last_attempt_at: now, requests_used: @connection.requests_used + 1,
                          quota_date: now.utc.to_date)
      { key: @connection.api_key, fingerprint: credential_fingerprint,
        entitlement: @entitlement.settings.deep_dup, attempted_at: @connection.reload.last_attempt_at }
    end
    return false unless reservation.is_a?(Hash)
    snapshot = @client_factory.call(reservation.fetch(:key)).snapshot(ticker)
    @connection.with_lock do
      @connection.expire_evidence!(@entitlement)
      unless credential_fingerprint == reservation.fetch(:fingerprint) &&
             @connection.last_attempt_at == reservation.fetch(:attempted_at) &&
             @entitlement.approved? && @entitlement.settings == reservation.fetch(:entitlement)
        next fail_with("credentials_or_rights_changed")
      end
      snapshot["entitlement"] = @entitlement.metadata
      @connection.update!(snapshot: snapshot, last_success_at: Time.current, last_error: nil)
      true
    end
  rescue EquiblesClient::EvidenceError => error
    @connection.with_lock { fail_with(ERRORS.include?(error.message) ? error.message : "provider_unavailable") }
  end

  private

  def credential_fingerprint
    Digest::SHA256.hexdigest(@connection.read_attribute_before_type_cast(:api_key).to_s)
  end

  def fail_with(code)
    attributes = { last_error: code }
    attributes[:snapshot] = {} if code == "credentials_or_rights_changed"
    @connection.update!(attributes)
    Rails.logger.warn("equibles_evidence refresh_failed user_id=#{@connection.user_id} code=#{code}")
    false
  end
end
