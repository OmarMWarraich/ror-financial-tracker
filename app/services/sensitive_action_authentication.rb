class SensitiveActionAuthentication
  def self.verify(user, password)
    verified = false
    user.with_lock do
      return false if user.sensitive_action_locked_until && user.sensitive_action_locked_until > Time.current

      if password.is_a?(String) && password.bytesize <= 1024 && user.valid_password?(password)
        user.update!(sensitive_action_failures: 0, sensitive_action_locked_until: nil)
        verified = true
      else
        failures = user.sensitive_action_locked_until ? 1 : user.sensitive_action_failures + 1
        user.update!(sensitive_action_failures: failures,
                     sensitive_action_locked_until: failures >= 5 ? 15.minutes.from_now : nil)
        Rails.logger.warn("sensitive_action authentication failed user=#{user.id}")
      end
    end
    verified
  end
end
