require "test_helper"

class ResearchChatChannelTest < ActionCable::Channel::TestCase
  setup do
    @user = users(:one)
    @conversation = @user.research_conversations.create!(scope: { evidence_mode: "fixture" },
      limits: Research::Agent::Limits::DEFAULT, expires_at: Time.current + 1.day)
    @lease, = ResearchChatSession.issue!(@user)
    stub_connection current_user: @user, current_chat_session_id: @lease.id
    lease = @lease
    connection.define_singleton_method(:chat_access?) { lease.reload.valid_access? }
  end

  test "only owned subscriptions start a stream and revoked or expired access stops it" do
    subscribe conversation_id: @conversation.id
    assert subscription.confirmed?
    assert_has_stream Research::Chat.stream(@conversation)
    @lease.update!(revoked_at: Time.current)
    connection.define_singleton_method(:close) { |**_| }
    subscription.verify_access
    assert_no_streams
  end

  test "anonymous cross-owner and expired leases cannot subscribe" do
    other = users(:two).research_conversations.create!(scope: {}, limits: {}, expires_at: Time.current + 1.day)
    subscribe conversation_id: other.id
    assert subscription.rejected?
    assert_no_streams
    @lease.update!(expires_at: Time.current - 1.second)
    subscribe conversation_id: @conversation.id
    assert subscription.rejected?
  end
end
