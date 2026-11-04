class KrakenMonitoringRefresh
  MIN_INTERVAL = 60.seconds

  def self.call(connection)
    error = nil
    connection.with_lock do
      begin
        raise KrakenReadOnlyClient::Error, "Exchange monitoring is disabled pending product, geography, and terms review." unless KrakenMonitoringPolicy.approved?(connection.user)
        raise KrakenReadOnlyClient::Error, "Configure credential encryption before connecting." unless BrokerConnection.encryption_ready?
        if %w[pending verified].include?(connection.state) && connection.expires_at <= Time.current
          connection.update!(state: "expired", api_key: nil, api_secret: nil)
        end
        raise KrakenReadOnlyClient::Error, "This connection is inactive. Create a new dedicated key to reconnect." unless connection.active?
        if connection.last_attempt_at && connection.last_attempt_at > MIN_INTERVAL.ago
          raise KrakenReadOnlyClient::Error, "Refresh is limited to once per minute; no new request was sent."
        end

        connection.update!(last_attempt_at: Time.current)
        client = KrakenReadOnlyClient.new(api_key: connection.api_key, api_secret: connection.api_secret,
                                         nonce: -> {
                                           nonce = [connection.last_nonce + 1, (Time.current.to_f * 1000).to_i].max
                                           connection.update!(last_nonce: nonce)
                                           nonce
                                         })
        info = client.key_info(include_history: connection.include_history)
        if connection.account_identifier.present? && connection.account_identifier != info[:identifier]
          raise KrakenReadOnlyClient::PermissionError, "The key account changed. Disconnect and review a new connection."
        end
        balances = client.balances
        history = connection.include_history ? client.trades : nil
        connection.update!(state: "verified", account_identifier: info[:identifier],
                           verified_permissions: info[:permissions], balance_payload: JSON.generate(balances),
                           history_payload: history && JSON.generate(history), received_at: Time.current,
                           expires_at: [connection.expires_at, info[:expires_at]].compact.min, last_error: nil)
      rescue KrakenReadOnlyClient::Error => exception
        attributes = { last_error: exception.message }
        if exception.is_a?(KrakenReadOnlyClient::PermissionError) || exception.is_a?(KrakenReadOnlyClient::RevokedError)
          attributes.merge!(state: exception.is_a?(KrakenReadOnlyClient::RevokedError) ? "revoked" : "blocked",
                            api_key: nil, api_secret: nil)
        end
        connection.update!(attributes)
        Rails.logger.warn("kraken_monitoring refresh failed connection=#{connection.id} category=#{exception.class.name}")
        error = exception
      end
    end
    raise error if error

    connection
  end
end
