class UserStocksController < ApplicationController
  def create
    unless current_user.can_track_stock?(params[:ticker])
      redirect_to my_portfolio_path, alert: "Stock is already tracked or your ten-stock limit has been reached.",
                                    status: :see_other
      return
    end

    @user = current_user
    @tracked_stocks = current_user.stocks
    stock = Stock.check_db(params[:ticker])
    if stock.blank?
      stock = Stock.new_lookup(params[:ticker], user: current_user)
      unless stock&.save
        redirect_to my_portfolio_path, alert: "Stock data is unavailable. Check the ticker or try again later.",
                                      status: :see_other
        return
      end
    end
    @user_stock = UserStock.create(user: current_user, stock: stock)
    flash.now[:notice] = "Stock #{stock.name} was successfully added to your portfolio"
    
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.append("stocks-list", partial: "stocks/list", locals: { tracked_stocks: @tracked_stocks }) +
                             turbo_stream.replace("posts", partial: "users/result") + 
                             turbo_stream.replace("search-form", partial: "users/search_form") +
                             turbo_stream.replace("flash", partial: "layouts/messages")
      end
      format.html { redirect_to my_portfolio_path }
    end
  end

  def destroy
    @user = current_user
    @tracked_stocks = current_user.stocks
    user_stock = current_user.user_stocks.find_by!(stock_id: params[:id])
    stock = user_stock.stock
    user_stock.destroy
    flash.now[:alert] = "#{stock.ticker.upcase} was successfully removed from your portfolio"

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("flash", partial: "layouts/messages") +
                             turbo_stream.replace("stocks-list", partial: "stocks/list", locals: { tracked_stocks: @tracked_stocks }) 
      end
      format.html { redirect_to my_portfolio_path }
    end
end
end