class UserStocksController < ApplicationController
  def create
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
end