class MarketDashboardsController < ApplicationController
  skip_before_action :authenticate_user!, only: %i[show refresh listings]
  prepend_before_action :disable_caching
  before_action :require_local_showcase, only: %i[show refresh listings]

  def show
    @tickers = MarketDashboard::DEFAULT_TICKERS.join(", ")
    @disabled = !MarketDashboard.enabled?
    return if @disabled
    selected = if params[:selected].present?
      MarketDashboard.tickers(params[:selected], limit: 1).first
    elsif user_signed_in?
      dashboard_preferences_for_show["selected"]
    end
    service = MarketDashboard.new
    @dashboard = selected ? service.call(mode: "leaders", selected_ticker: selected) : service.call(mode: "leaders")
  rescue EquiblesClient::EvidenceError => error
    Rails.logger.warn("dashboard initial_load_rejected code=#{error.message}")
    @error = error.message.humanize
    render :show, status: :service_unavailable
  end

  def listings
    @query = params.fetch(:query, "")
    offset = params.fetch(:offset, "0")
    unless (offset.is_a?(String) && offset.match?(/\A\d{1,7}\z/)) ||
           (offset.is_a?(Integer) && offset.between?(0, 1_000_000))
      raise EquiblesClient::EvidenceError, "invalid_listing_search"
    end
    @listings = MarketDashboard.new.listings(query: @query, offset: offset.to_i)
    if request.format.json?
      render json: { html: render_to_string(partial: "listing_results", formats: [:html], locals: { listings: @listings }),
        next_offset: @listings[:next_offset] }
    end
  rescue EquiblesClient::EvidenceError => error
    Rails.logger.warn("dashboard listings_rejected code=#{error.message}")
    @error = error.message.humanize
    if request.format.json?
      render json: { error: @error }, status: :unprocessable_entity
    else
      render :listings, status: :unprocessable_entity
    end
  end

  def preferences
    render json: DashboardPreferences.new(current_user).read
  rescue Redis::BaseError, RedisClient::Error, JSON::ParserError, DashboardPreferences::Invalid => error
    Rails.logger.warn("dashboard preferences_read_failed type=#{error.class.name}")
    render json: { error: "Redis preferences unavailable" }, status: :service_unavailable
  end

  def save_preferences
    value = params[:preferences]
    raise DashboardPreferences::Invalid unless value.is_a?(ActionController::Parameters)
    state = value.to_unsafe_h
    render json: DashboardPreferences.new(current_user).write(state)
  rescue DashboardPreferences::Invalid, ActionController::ParameterMissing => error
    Rails.logger.warn("dashboard preferences_rejected type=#{error.class.name}")
    render json: { error: "Invalid UI preferences; market data cannot be stored here" }, status: :unprocessable_entity
  rescue Redis::BaseError, RedisClient::Error => error
    Rails.logger.warn("dashboard preferences_write_failed type=#{error.class.name}")
    render json: { error: "Redis synchronization unavailable; local UI preferences may remain saved" }, status: :service_unavailable
  end

  def refresh
    @tickers = params[:tickers]
    mode = params[:mode].presence || "manual"
    service = MarketDashboard.new(tickers: @tickers.presence || MarketDashboard::DEFAULT_TICKERS.join(","))
    @dashboard = if mode == "manual"
      service.call
    elsif mode == "detail" && !request.format.json?
      service.call(mode: "leaders", selected_ticker: MarketDashboard.tickers(@tickers, limit: 1).first)
    elsif %w[leaders quotes].include?(mode) && params[:selected].present?
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

  def dashboard_preferences_for_show
    DashboardPreferences.new(current_user).read
  rescue Redis::BaseError, RedisClient::Error, JSON::ParserError, DashboardPreferences::Invalid => error
    Rails.logger.warn("dashboard preferences_restore_failed type=#{error.class.name}")
    @preferences_error = "Redis preferences unavailable; fresh market data is still requested."
    { "selected" => nil }
  end

  def disable_caching
    response.headers["Cache-Control"] = "no-store"
    response.headers["Pragma"] = "no-cache"
  end

  def require_local_showcase
    return if action_name == "show" && !MarketDashboard.enabled?
    return head :not_found unless MarketDashboard.enabled?
    unless PrivateRequestTransport::COMPOSE_HOSTS.include?(request.host) && PrivateRequestTransport.allowed?(request)
      head :forbidden
    end
  end
end
