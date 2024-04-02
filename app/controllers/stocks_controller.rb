class StocksController < ApplicationController
  def search
    if params[:stock].present?
      @stock = Stock.new_lookup(params[:stock])
      @stocks = Stock.all
      @tracked_stocks = current_user.stocks
      if @stock
        respond_to do |format|
          format.turbo_stream do 
            render turbo_stream: turbo_stream.append("posts", partial: "users/result", locals: { stock: @stock }) +
                                 turbo_stream.replace("search-form", partial: "users/search_form") +
                                 turbo_stream.replace("flash", partial: "layouts/messages")
          end
        end
      else
        flash[:alert] = "Please enter a valid symbol to search"
        redirect_to my_portfolio_path
      end
    else
      flash[:alert] = "Please enter a symbol to search"
      redirect_to my_portfolio_path
    end
  end
end
