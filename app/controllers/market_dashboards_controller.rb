class MarketDashboardsController < ApplicationController
  prepend_before_action :disable_caching
  before_action :require_local_showcase

  def show
    @tickers = MarketDashboard::DEFAULT_TICKERS.join(", ")
  end

  def refresh
    @tickers = params[:tickers]
    mode = params[:mode].presence || "manual"
    service = MarketDashboard.new(tickers: @tickers.presence || MarketDashboard::DEFAULT_TICKERS.join(","))
    @dashboard = if mode == "manual"
      service.call
    elsif mode == "detail" && !request.format.json?
      service.call(mode: "leaders", selected_ticker: MarketDashboard.tickers(@tickers, limit: 1).first)
    elsif mode == "leaders" && params[:selected].present?
      service.call(mode: mode, selected_ticker: MarketDashboard.tickers(params[:selected], limit: 1).first)
    else
      service.call(mode: mode)
    end
    if request.format.json?
      if mode == "quotes"
        render json: @dashboard
      else
        partial = mode == "detail" ? "detail" : "board"
        render json: { html: render_to_string(partial: partial, formats: [:html], locals: { dashboard: @dashboard }),
          errors: @dashboard[:errors], received_at: @dashboard[:received_at] }
      end
      return
    end
    render :show
  rescue EquiblesClient::EvidenceError => error
    Rails.logger.warn("market_dashboard refresh_rejected code=#{error.message}")
    @error = error.message.humanize
    if request.format.json?
      render json: { error: @error }, status: :unprocessable_entity
      return
    end
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
