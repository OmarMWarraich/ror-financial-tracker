class ResearchChatChannel < ApplicationCable::Channel
  periodically :verify_access, every: 5.seconds

  def subscribed
    return reject unless connection.chat_access?
    conversation = current_user.research_conversations.find_by(id: params[:conversation_id])
    return reject unless conversation
    stream_from Research::Chat.stream(conversation), coder: ActiveSupport::JSON do |message|
      if connection.chat_access?
        transmit(message)
      else
        verify_access
      end
    end
  end

  def verify_access
    return if connection.chat_access?
    stop_all_streams
    connection.close(reason: "unauthorized", reconnect: false)
  end
end
