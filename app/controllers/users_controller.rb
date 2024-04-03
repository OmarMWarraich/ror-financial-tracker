class UsersController < ApplicationController
  def my_portfolio
    @tracked_stocks = current_user.stocks
  end

  def my_friends
    @friends = current_user.friends
  end

  def search
    if params[:friend].present?
      @friend = params[:friend]
      if @friend
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.append("friend-result", partial: "users/friend_result", locals: { friend: @friend }) +
                                 turbo_stream.replace("friends-search-form", partial: "users/friends_search_form")                                  
          end
        end
      else
        flash[:alert] = "Could not find user"
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.replace("flash", partial: "layouts/messages")
          end
        end
      end
    else
      flash[:alert] = "Please enter a username to search"
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace("flash", partial: "layouts/messages")
        end
      end
    end
  end
end
