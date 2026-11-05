class PrivateRequestTransport
  LOOPBACK_HOSTS = %w[localhost 127.0.0.1 ::1].freeze
  COMPOSE_HOSTS = (LOOPBACK_HOSTS + ["10.0.2.2"]).freeze

  def self.allowed?(request)
    return true if request.ssl?
    return false unless Rails.env.development? || Rails.env.test?
    return true if request.local? && LOOPBACK_HOSTS.include?(request.host)

    Rails.env.development? && ENV["LOCAL_COMPOSE_HTTP"] == "1" && COMPOSE_HOSTS.include?(request.host)
  end
end
