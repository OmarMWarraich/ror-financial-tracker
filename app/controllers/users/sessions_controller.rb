class Users::SessionsController < Devise::SessionsController
  before_action :revoke_research_chat_session, only: :destroy

  private

  def revoke_research_chat_session
    token = session.delete(:research_chat_token)
    record = current_user&.research_chat_sessions&.find_by(token_digest: Digest::SHA256.hexdigest(token.to_s))
    return unless record
    record.update!(revoked_at: Time.current)
    ActionCable.server.remote_connections.where(current_user: current_user, current_chat_session_id: record.id).disconnect(reconnect: false)
  rescue Redis::BaseError, RedisClient::Error => error
    Rails.logger.warn("Research chat lease #{record.id} logout disconnect unavailable type=#{error.class.name}; revocation persists")
  end
end
