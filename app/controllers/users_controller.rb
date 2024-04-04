class UsersController < ApplicationController
  def my_portfolio
    @tracked_stocks = current_user.stocks
    @user = current_user
  end

  def my_friends
    @friends = current_user.friends
  end

  def show
    @user = User.find(params[:id])
    @tracked_stocks = @user.stocks
  end

  def search
    if params[:friend].present?
      @friends = User.search(params[:friend])
      @friends = current_user.except_current_user(@friends)
      if @friends
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.append("friend-result", partial: "users/friend_result" ) +
                                 turbo_stream.replace("friends-search-form", partial: "users/friends_search_form")                                  
          end
        end
      else
        flash.now[:alert] = "Could not find user"
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.replace("flash", partial: "layouts/messages") +
                                 turbo_stream.append("friend-result", partial: "users/friend_result")
          end
        end
      end
    else
      flash.now[:alert] = "Please enter a username to search"
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace("flash", partial: "layouts/messages")
        end
      end
    end
  end
end
