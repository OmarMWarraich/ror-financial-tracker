class SandboxAccountsController < ApplicationController
  prepend_before_action :sandbox_private_response
  before_action :sandbox_secure_transport
  rescue_from SandboxLedger::Denied, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique,
              with: :sandbox_denied

  def index
    @account = SandboxAccount.find_by(user_id: current_user.id)
    return render :new unless @account

    redirect_to sandbox_account_path(@account)
  end

  def show
    @account = SandboxAccount.where(user_id: current_user.id).find(params[:id])
    @mandates = @account.sandbox_mandates.order(id: :desc)
    @orders = @account.sandbox_orders.order(id: :desc).limit(30)
    @events = @account.sandbox_events.order(id: :desc).limit(50)
    @request_key = SecureRandom.uuid
  end

  def create
    unless SensitiveActionAuthentication.verify(current_user, params[:current_password])
      raise SandboxLedger::Denied, "Confirm your current application password."
    end
    account = SandboxLedger.new(current_user).create_account!(initial_cash: params[:initial_cash])
    redirect_to sandbox_account_path(account), notice: "Independent SYNTHETIC USD account created. No money or external account connected."
  end

  def load_fixture
    SandboxLedger.new(current_user).load_fixture!(account_id: params[:id], fixture_key: params[:fixture_key])
    redirect_to sandbox_account_path(params[:id]), notice: "Fictional fixture loaded for 15 minutes; this is not market freshness."
  end

  private

  def sandbox_private_response
    response.headers["Cache-Control"] = "no-store, private"
    response.headers["Referrer-Policy"] = "no-referrer"
  end

  def sandbox_secure_transport
    head :forbidden unless PrivateRequestTransport.allowed?(request)
  end

  def sandbox_denied(exception)
    redirect_to sandbox_accounts_path, alert: exception.is_a?(ActiveRecord::RecordNotUnique) ?
      "A synthetic account already exists; reload it." : exception.message
  end
end
