module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user, :current_chat_session_id

    def connect
      reject_unauthorized_connection unless Research::Chat.enabled? && !Research::RestoreGate.pending?
      self.current_user = env["warden"]&.user(:user)
      reject_unauthorized_connection unless current_user
      token = request.session[:research_chat_token]
      record = current_user.research_chat_sessions.find_by(token_digest: Digest::SHA256.hexdigest(token.to_s))
      reject_unauthorized_connection unless token.present? && record&.valid_access?
      self.current_chat_session_id = record.id
    end

    def chat_access?
      Research::Chat.enabled? && !Research::RestoreGate.pending? &&
        current_user.research_chat_sessions.find_by(id: current_chat_session_id)&.valid_access?
    end
  end
end
