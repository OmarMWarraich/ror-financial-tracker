class ResearchChatsController < ApplicationController
  before_action :enable_chat
  before_action :authorize_chat_session
  before_action :load_conversation, only: %i[show snapshot stop]

  def index
    @conversations = current_user.research_conversations.where("scope ->> 'evidence_mode' = ?", "fixture").order(id: :desc).limit(20)
  end

  def show
    load_messages
  end

  def snapshot
    load_messages
    render partial: "state"
  end

  def create
    input = params.require(:research_chat).permit(:question, :request_key, :conversation_id, :workflow,
      preferences: %i[output_tokens tools seconds])
    conversation = current_user.research_conversations.find(input[:conversation_id]) if input[:conversation_id].present?
    workflow = conversation ? conversation.scope["workflow"] : (input[:workflow].presence || Research::Agent::EarningsWorkflow::ID)
    if conversation && input[:workflow].present? && input[:workflow] != workflow
      raise Research::Error.new("workflow_not_approved")
    end
    preferences = (input[:preferences] || {}).to_h.reject { |_, value| value.blank? }.transform_values do |value|
      raise Research::Error.new("invalid_agent_limits") unless value.is_a?(String) && value.match?(/\A[0-9]{1,5}\z/)
      value.to_i
    end
    run = Research::Agent::Lifecycle.submit!(user: current_user, query: input[:question],
      request_key: input[:request_key], conversation: conversation,
      preferences: preferences, workflow: workflow, query_mode: workflow ? "latest_earnings" : "current",
      listing_identity: "SYNTH:ALPHA", fiscal_year: 2026, fiscal_quarter: 3, evidence_mode: "fixture")
    redirect_to research_chat_path(run.conversation), status: :see_other
  rescue Research::Error => error
    Rails.logger.warn("Research chat submission rejected user=#{current_user.id} code=#{error.code}")
    existing = current_user.research_agent_runs.find_by(request_key: input&.[](:request_key))
    redirect_to(existing&.conversation_id ? research_chat_path(existing.conversation_id) : research_chats_path,
      alert: "Research request rejected: #{error.code}. Refresh only reloads saved state; it never resubmits paid work.",
      status: :see_other)
  end

  def stop
    run = @conversation.runs.find(params[:run_id])
    Research::Agent::Lifecycle.stop!(user: current_user, run_id: run.id)
    Research::Chat::Updates.new(run).refresh!
    redirect_to research_chat_path(@conversation), notice: "Stop requested. Accepted provider work may still be billed; cancellation is not a refund.", status: :see_other
  rescue Research::Error => error
    Rails.logger.warn("Research chat stop rejected user=#{current_user.id} code=#{error.code}")
    redirect_to research_chat_path(@conversation), alert: "Stop rejected: #{error.code}", status: :see_other
  end

  private

  def enable_chat
    response.headers["Cache-Control"] = "no-store"
    render plain: "Research chat is disabled.", status: :not_found unless Research::Chat.enabled?
  end

  def authorize_chat_session
    token = session[:research_chat_token]
    record = current_user.research_chat_sessions.find_by(token_digest: Digest::SHA256.hexdigest(token.to_s)) if token
    return if record&.valid_access?
    if action_name == "snapshot"
      Rails.logger.warn("Research chat snapshot rejected user=#{current_user.id} code=chat_session_expired")
      return render plain: "Research chat session expired. Reload the page or sign in again.", status: :unauthorized
    end
    _, session[:research_chat_token] = ResearchChatSession.issue!(current_user)
  end

  def load_conversation
    @conversation = current_user.research_conversations.find(params[:id])
    raise ActiveRecord::RecordNotFound unless @conversation.scope["evidence_mode"] == "fixture"
  end

  def load_messages
    @runs = @conversation.runs.includes(:model_attempts, :tool_attempts).order(:id)
    @messages = @conversation.messages.includes(:run).order(:id).map do |message|
      { record: message, text: message.readable_content!, sources: message.sources }
    rescue Research::Error => error
      Rails.logger.warn("Research chat message #{message.id} unavailable code=#{error.code}")
      { record: message, error: error.code, sources: [] }
    end
  end
end
