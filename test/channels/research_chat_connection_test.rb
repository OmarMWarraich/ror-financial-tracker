require "test_helper"

class ResearchChatConnectionTest < ActionCable::Connection::TestCase
  tests ApplicationCable::Connection

  setup do
    @previous = ENV["RESEARCH_CHAT_ENABLED"]
    ENV["RESEARCH_CHAT_ENABLED"] = "1"
    @user = users(:one)
    @lease, @token = ResearchChatSession.issue!(@user)
    @warden = Struct.new(:owner) { def user(_) = owner }.new(@user)
  end

  teardown do
    @previous ? ENV["RESEARCH_CHAT_ENABLED"] = @previous : ENV.delete("RESEARCH_CHAT_ENABLED")
  end

  test "warden session and server-side lease are both required with no query-string credentials" do
    connect "/cable", session: { research_chat_token: @token }, env: { "warden" => @warden }
    assert_equal @user, connection.current_user
    assert_equal @lease.id, connection.current_chat_session_id
    assert connection.chat_access?
    @lease.update!(revoked_at: Time.current)
    assert_not connection.chat_access?
  end

  test "anonymous missing expired password-reset and disabled sessions are rejected" do
    assert_reject_connection { connect "/cable", session: { research_chat_token: @token } }
    assert_reject_connection { connect "/cable", env: { "warden" => @warden }, params: { token: @token } }
    @lease.update!(expires_at: Time.current - 1.second)
    assert_reject_connection { connect "/cable", session: { research_chat_token: @token }, env: { "warden" => @warden } }
    @lease.update!(expires_at: Time.current + 1.day)
    @user.update!(password: "original-updated-fixture-password")
    assert_reject_connection { connect "/cable", session: { research_chat_token: @token }, env: { "warden" => @warden } }
    ENV["RESEARCH_CHAT_ENABLED"] = "0"
    assert_reject_connection { connect "/cable", session: { research_chat_token: @token }, env: { "warden" => @warden } }
  end
end
