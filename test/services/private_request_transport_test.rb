require "test_helper"

class PrivateRequestTransportTest < ActiveSupport::TestCase
  Request = Struct.new(:host, :secure, :loopback) do
    def ssl? = secure
    def local? = loopback
  end

  test "HTTPS remains required outside explicitly isolated local development" do
    original = ENV["LOCAL_COMPOSE_HTTP"]
    ENV["LOCAL_COMPOSE_HTTP"] = "1"
    Rails.stub(:env, "production".inquiry) do
      refute PrivateRequestTransport.allowed?(Request.new("localhost", false, true))
      assert PrivateRequestTransport.allowed?(Request.new("example.test", true, false))
    end
    Rails.stub(:env, "development".inquiry) do
      assert PrivateRequestTransport.allowed?(Request.new("127.0.0.1", false, false))
      assert PrivateRequestTransport.allowed?(Request.new("10.0.2.2", false, false))
      refute PrivateRequestTransport.allowed?(Request.new("192.168.1.5", false, false))
      refute PrivateRequestTransport.allowed?(Request.new("attacker.test", false, true))
    end
  ensure
    ENV["LOCAL_COMPOSE_HTTP"] = original
  end

  test "container HTTP opt-in is absent by default and cannot bypass tests or remote hosts" do
    original = ENV.delete("LOCAL_COMPOSE_HTTP")
    Rails.stub(:env, "development".inquiry) do
      refute PrivateRequestTransport.allowed?(Request.new("127.0.0.1", false, false))
      assert PrivateRequestTransport.allowed?(Request.new("localhost", false, true))
    end
    ENV["LOCAL_COMPOSE_HTTP"] = "1"
    Rails.stub(:env, "test".inquiry) do
      refute PrivateRequestTransport.allowed?(Request.new("127.0.0.1", false, false))
    end
  ensure
    ENV["LOCAL_COMPOSE_HTTP"] = original
  end
end
