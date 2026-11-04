class BrokerConnectionsController < ApplicationController
  rescue_from ActiveRecord::Encryption::Errors::Decryption,
              ActiveRecord::Encryption::Errors::Configuration, with: :encryption_unavailable
  before_action :prevent_private_caching
  before_action :require_secure_transport
  before_action :find_connection, only: %i[refresh destroy request_elevation]
  before_action :verify_step_up, only: %i[create destroy request_elevation]

  def index
    @connections = current_user.broker_connections.order(:created_at)
    @connection = current_user.broker_connections.new
    @encryption_ready = BrokerConnection.encryption_ready?
    @monitoring_enabled = @encryption_ready && KrakenMonitoringPolicy.approved?(current_user)
  end

  def create
    unless BrokerConnection.encryption_ready? && KrakenMonitoringPolicy.approved?(current_user)
      return redirect_to broker_connections_path, alert: "Connections are disabled until encryption, product eligibility, and API terms are reviewed."
    end
    unless params[:owns_account] == "1"
      return redirect_to broker_connections_path, alert: "Confirm that this is your own account and a dedicated key."
    end

    @connection = current_user.broker_connections.new(connection_params)
    @connection.expires_at = 30.days.from_now
    if @connection.save
      redirect_to broker_connections_path, notice: "Connection saved pending read-only scope verification. Refresh explicitly to verify; no request has been sent."
    else
      redirect_to broker_connections_path, alert: @connection.errors.full_messages.join(". ")
    end
  rescue ActiveRecord::RecordNotUnique
    redirect_to broker_connections_path, alert: "This key is already registered. Use a new dedicated key."
  end

  def refresh
    KrakenMonitoringRefresh.call(@connection)
    redirect_to broker_connections_path, notice: "Read-only exchange evidence refreshed. No equity brokerage or trading authority is implied."
  rescue KrakenReadOnlyClient::Error => exception
    redirect_to broker_connections_path, alert: exception.message
  end

  def destroy
    @connection.disconnect!
    redirect_to broker_connections_path, notice: "Disconnected; secrets and retained account evidence removed. Revoke the API key at Kraken too."
  end

  def request_elevation
    @connection.request_elevation!
    redirect_to broker_connections_path, notice: "Review requested only. Eligibility, a separate key, paper acceptance, mandate, and live approval remain required. Trading is unavailable."
  rescue KrakenReadOnlyClient::Error => exception
    redirect_to broker_connections_path, alert: exception.message
  end

  private

  def prevent_private_caching
    response.headers["Cache-Control"] = "no-store, private"
    response.headers["Referrer-Policy"] = "no-referrer"
  end

  def encryption_unavailable(exception)
    Rails.logger.error("kraken_monitoring encryption unavailable category=#{exception.class.name}")
    response.headers["Cache-Control"] = "no-store, private"
    render plain: "Encrypted account evidence is unavailable. Restore the original deployment encryption keys; do not replace credentials.", status: :service_unavailable
  end

  def find_connection
    @connection = current_user.broker_connections.find(params[:id])
  end

  def verify_step_up
    unless SensitiveActionAuthentication.verify(current_user, params[:current_password])
      redirect_to broker_connections_path, alert: "Confirm your current application password. Repeated failures lock sensitive actions for 15 minutes."
    end
  end

  def require_secure_transport
    unless request.ssl? || (Rails.env.development? || Rails.env.test?) &&
           request.local? && %w[localhost 127.0.0.1 ::1].include?(request.host)
      head :forbidden
    end
  end

  def connection_params
    params.require(:broker_connection).permit(:label, :api_key, :api_secret, :include_history)
  end
end
