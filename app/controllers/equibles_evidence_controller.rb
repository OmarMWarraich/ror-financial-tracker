class EquiblesEvidenceController < ApplicationController
  prepend_before_action :disable_caching
  before_action :require_secure_transport
  before_action :load_evidence
  before_action :verify_step_up, only: %i[update destroy]
  rescue_from ActiveRecord::Encryption::Errors::Base, with: :credential_configuration_error

  def show
    @connection&.with_lock { @connection.expire_evidence!(@entitlement) }
    @snapshot = EquiblesConnection.encryption_configured? ? (@connection&.snapshot || {}) : {}
  end

  def update
    unless @entitlement.approved? && EquiblesConnection.encryption_configured?
      return redirect_to equibles_evidence_path, alert: "Equibles rights or encryption are not configured."
    end
    key = params[:api_key]
    unless key.is_a?(String) && key.match?(/\Aeq_[^\s]{1,250}\z/)
      return redirect_to equibles_evidence_path, alert: "Enter a valid personal Equibles API key."
    end
    @connection ||= EquiblesConnection.create_or_find_by!(user: current_user)
    @connection.with_lock { @connection.update!(api_key: key, snapshot: {}, last_success_at: nil, last_error: nil) }
    redirect_to equibles_evidence_path, notice: "Personal key saved. No provider request was made."
  end

  def refresh
    unless @connection
      return redirect_to equibles_evidence_path, alert: "Connect your own permitted subscription first."
    end
    success = EquiblesEvidenceRefresh.new(@connection).call(params[:ticker])
    redirect_to equibles_evidence_path,
                success ? { notice: "Evidence refreshed; timing and permitted use remain explicit." } :
                          { alert: "Refresh failed: #{@connection.last_error.humanize}. Previous evidence was not refreshed." }
  end

  def destroy
    @connection&.with_lock do
      @connection.update!(api_key: nil, snapshot: {}, last_success_at: nil, last_error: nil)
    end
    redirect_to equibles_evidence_path, notice: "Key and evidence removed. Revoke the key with Equibles separately."
  end

  private

  def disable_caching
    response.headers["Cache-Control"] = "no-store"
    response.headers["Pragma"] = "no-cache"
  end

  def credential_configuration_error
    redirect_to equibles_evidence_path, alert: "Credentials unavailable. Check encryption configuration; no provider request was made."
  end

  def load_evidence
    @connection = EquiblesConnection.find_by(user_id: current_user.id)
    @entitlement = EquiblesEntitlement.new(current_user)
  end

  def verify_step_up
    unless SensitiveActionAuthentication.verify(current_user, params[:current_password])
      redirect_to equibles_evidence_path, alert: "Confirm your current application password. Repeated failures lock sensitive actions for 15 minutes."
    end
  end

  def require_secure_transport
    head :forbidden unless PrivateRequestTransport.allowed?(request)
  end
end
