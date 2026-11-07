class ApplicationController < ActionController::Base
  before_action :check_restore_gate
  before_action :authenticate_user!
  before_action :configure_permitted_parameters, if: :devise_controller?

  protected

  def check_restore_gate
    if Research::RestoreGate.pending?
      response.headers["Cache-Control"] = "no-store"
      render plain: "Restore review and research purge required before serving traffic.", status: :service_unavailable
    end
  end

  # Add username to devise registration
  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:account_update, keys: [:first_name, :last_name])
    devise_parameter_sanitizer.permit(:sign_up, keys: [:first_name, :last_name])
  end
end
