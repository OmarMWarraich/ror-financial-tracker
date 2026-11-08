require "redis"

class DashboardPreferences
  TTL = 86_400
  class Invalid < StandardError; end

  def self.scope(user)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, "dashboard-ui-v1:#{user.id}")
  end

  def self.key(user)
    "dashboard-ui:v1:#{Rails.env}:owner:#{user.id}"
  end

  def initialize(user, redis: nil)
    @key = self.class.key(user)
    @redis = redis || Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"), timeout: 2, reconnect_attempts: 0)
  end

  def read
    value = @redis.get(@key)
    value ? validate(JSON.parse(value)) : { "version" => 1, "ranges" => {}, "selected" => nil }
  ensure
    @redis.close
  end

  def write(value)
    state = validate(value)
    @redis.set(@key, JSON.generate(state), ex: TTL)
    state
  ensure
    @redis.close
  end

  def validate(state)
    unless state.is_a?(Hash) && state.keys.sort == %w[ranges selected version] &&
           state["version"] == 1 && state["ranges"].is_a?(Hash) && state["ranges"].size <= 10 &&
           (state["selected"].nil? || ticker?(state["selected"])) &&
           state["ranges"].all? { |ticker, range| ticker?(ticker) && %w[5D 1M 6M 1Y].include?(range) }
      raise Invalid, "Only bounded chart ranges and selected ticker may be persisted"
    end
    state
  end

  private

  def ticker?(value)
    value.is_a?(String) && value.match?(/\A[A-Z][A-Z0-9-]{0,19}\z/)
  end
end
