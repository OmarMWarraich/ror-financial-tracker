class DepositInformationController < ApplicationController
  prepend_before_action :prevent_private_caching
  before_action :require_secure_transport

  def show
    @capability = DepositInformationCapability.new
  end

  def check
    unless SensitiveActionAuthentication.verify(current_user, params[:current_password])
      @capability = DepositInformationCapability.new
      flash.now[:alert] = "Confirm your current application password. Repeated failures lock sensitive actions for 15 minutes."
      return render :show, status: :unprocessable_entity
    end

    @capability = DepositInformationCapability.new
    @checked = true
    render :show
  end

  private

  def prevent_private_caching
    response.headers["Cache-Control"] = "no-store, private"
    response.headers["Referrer-Policy"] = "no-referrer"
  end

  def require_secure_transport
    head :forbidden unless PrivateRequestTransport.allowed?(request)
  end
end
