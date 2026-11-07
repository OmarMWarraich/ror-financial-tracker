module Research
  class SourceQuota
    def self.reserve!(request, allocation:, limit:)
      connection = request.user.equibles_connection.reload
      connection.with_lock("FOR UPDATE NOWAIT") do
        account_lock!(connection)
        today = Time.current.utc.to_date
        used = connection.quota_date == today ? connection.requests_used : 0
        if request.is_a?(ResearchAgentRun) && request.conversation_id
          settings = Agent::Policy.new(request.user).check!(request)
          check_capacity!(connection, settings: settings, additional: 0)
        end
        if (group_used(connection) + held(connection) >= allocation && !(request.is_a?(ResearchAgentRun) && request.conversation_id)) ||
           used >= allocation || request.source_requests >= limit
          raise Error.new("source_request_budget_exceeded")
        end
        connection.update!(quota_date: today, requests_used: used + 1, last_attempt_at: Time.current)
        request.update!(source_requests: request.source_requests + 1)
      end
    rescue ActiveRecord::LockWaitTimeout
      raise Error.new("source_account_busy")
    end

    def self.held(connection)
      ids = connection.quota_key_digest ? EquiblesConnection.where(quota_key_digest: connection.quota_key_digest).select(:id) : [connection.id]
      ResearchAgentRun.where(source_connection_id: ids, state: %w[queued running], budget_date: Time.current.utc.to_date)
        .sum { |run| [run.reserved_source_requests - run.source_requests, 0].max }
    end

    def self.group_used(connection)
      if connection.quota_key_digest
        usage = ResearchSourceUsage.where(key_digest: connection.quota_key_digest, budget_date: Time.current.utc.to_date)
        unrecorded = EquiblesConnection.where(quota_key_digest: connection.quota_key_digest, quota_date: Time.current.utc.to_date).sum do |row|
          [row.requests_used - usage.where(connection_id: row.id).sum(:requests_used), 0].max
        end
        usage.sum(:requests_used) + unrecorded
      else
        connection.quota_date == Time.current.utc.to_date ? connection.requests_used : 0
      end
    end

    def self.account_lock!(connection)
      account_key_lock!(connection.quota_key_digest || connection.id)
    end

    def self.account_key_lock!(identity)
      key = "equibles-quota:#{identity}"
      ApplicationRecord.connection.execute("SELECT pg_advisory_xact_lock(hashtext(#{ApplicationRecord.connection.quote(key)}))")
    end

    def self.check_capacity!(connection, settings:, additional:)
      connection.with_lock("FOR UPDATE NOWAIT") do
        connection.save! if connection.quota_key_digest.blank?
        account_lock!(connection)
        capacity, outside, reviewed = settings.values_at("quota_daily_capacity", "external_usage_reserved_requests", "quota_reviewed_until")
        unless capacity.is_a?(Integer) && capacity.between?(1, 30) && outside.is_a?(Integer) && outside.between?(0, capacity) &&
               reviewed.is_a?(String) && reviewed.match?(/T.*(?:Z|[+-]\d{2}:\d{2})\z/) &&
               Time.iso8601(reviewed) > Time.current && Time.iso8601(reviewed) <= Time.current + 1.day &&
               connection.quota_key_digest.present? && !EquiblesConnection.where(quota_key_digest: nil).where.not(api_key: nil).exists?
          raise Error.new("source_budget_unknown")
        end
        group = EquiblesConnection.where(quota_key_digest: connection.quota_key_digest)
        used = group_used(connection)
        held = self.held(connection) + additional
        raise Error.new("source_request_budget_exceeded") if used + outside + held > [capacity, settings.fetch("daily_source_requests")].min
        group.each do |row|
          observation = row.quota_observation
          next if observation.empty? || observation["date"] != Time.current.utc.to_date.iso8601
          raise Error.new("source_budget_unknown") if observation["unknown"] == true
          if observation["blocked"] || (observation["remaining"].is_a?(Integer) && observation["remaining"] < held)
            raise Error.new("source_request_budget_exceeded")
          end
        end
      end
    rescue ActiveRecord::LockWaitTimeout
      raise Error.new("source_account_busy")
    rescue ArgumentError
      raise Error.new("source_budget_unknown")
    end

    def self.observe!(run, status, headers)
      return unless run.conversation_id && run.source_connection
      settings = Agent::Policy.new(run.user).check!(run)
      observe_connection!(run.source_connection, status, headers, settings: settings)
    end

    def self.observe_connection!(connection, status, headers, settings:)
      values = headers.to_h.transform_keys { |key| key.to_s.downcase }
      remaining = values["x-ratelimit-remaining"] || values["ratelimit-remaining"]
      observation = { "date" => Time.current.utc.to_date.iso8601, "observed_at" => Time.current.utc.iso8601(6),
                      "blocked" => status == 429 }
      if remaining
        if settings["quota_header_semantics"] == "utc_daily_requests_remaining" && remaining.to_s.match?(/\A\d{1,6}\z/)
          observation["remaining"] = remaining.to_i
        else
          observation["unknown"] = true
        end
      end
      retry_after = values["retry-after"]
      observation["retry_after_seconds"] = retry_after.to_i if retry_after.to_s.match?(/\A\d{1,6}\z/)
      connection.with_lock do
        previous = connection.quota_observation
        previous = {} unless previous["date"] == observation["date"]
        observation["blocked"] ||= previous["blocked"]
        observation["unknown"] ||= previous["unknown"]
        values = [previous["remaining"], observation["remaining"]].select { |value| value.is_a?(Integer) }
        observation["remaining"] = values.min if values.any?
        connection.update!(quota_observation: observation)
      end
    end

    def self.prepare_key_groups!
      raise Error.new("equibles_credentials_unavailable") unless EquiblesConnection.encryption_configured?
      EquiblesConnection.where(quota_key_digest: nil).where.not(api_key: nil).find_each(&:save!)
    end
  end
end
