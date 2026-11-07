module Research
  class SourceQuota
    def self.reserve!(request, allocation:, limit:)
      connection = request.user.equibles_connection.reload
      connection.with_lock("FOR UPDATE NOWAIT") do
        today = Time.current.utc.to_date
        used = connection.quota_date == today ? connection.requests_used : 0
        if used >= allocation || request.source_requests >= limit
          raise Error.new("source_request_budget_exceeded")
        end
        connection.update!(quota_date: today, requests_used: used + 1, last_attempt_at: Time.current)
        request.update!(source_requests: request.source_requests + 1)
      end
    rescue ActiveRecord::LockWaitTimeout
      raise Error.new("source_account_busy")
    end
  end
end
