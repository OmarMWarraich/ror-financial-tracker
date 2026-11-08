class WelcomeController < ApplicationController
  def index
    redirect_to dashboard_path if request.path == root_path
  end
end
