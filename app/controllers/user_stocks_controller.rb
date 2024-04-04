class UserStocksController < ApplicationController
  def create
    @user = current_user
    @tracked_stocks = current_user.stocks
    stock = Stock.check_db(params[:ticker])
    if stock.blank?
      stock = Stock.new_lookup(params[:ticker])
      stock.save
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
    stock = Stock.find(params[:id])
    user_stock = UserStock.where(user_id: current_user.id, stock_id: stock.id).first
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