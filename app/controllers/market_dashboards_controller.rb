class MarketDashboardsController < ApplicationController
  prepend_before_action :disable_caching
  before_action :require_local_showcase

  def show
    @tickers = MarketDashboard::DEFAULT_TICKERS.join(", ")
  end

  def refresh
    @tickers = params[:tickers]
    @dashboard = MarketDashboard.new(tickers: @tickers).call
    render :show
  rescue EquiblesClient::EvidenceError => error
    Rails.logger.warn("market_dashboard refresh_rejected code=#{error.message}")
    @error = error.message.humanize
    @tickers = MarketDashboard::DEFAULT_TICKERS.join(", ")
    render :show, status: :unprocessable_entity
  end

  private

  def disable_caching
    response.headers["Cache-Control"] = "no-store"
    response.headers["Pragma"] = "no-cache"
  end

  def require_local_showcase
    return head :not_found unless MarketDashboard.enabled?
    unless PrivateRequestTransport::COMPOSE_HOSTS.include?(request.host) && PrivateRequestTransport.allowed?(request)
      head :forbidden
    end
  end
end
