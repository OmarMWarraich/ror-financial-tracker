class NativeConfigurationsController < ApplicationController
  skip_before_action :authenticate_user!, only: :show

  def show
    raise ActionController::BadRequest, "Unsupported native platform" unless %w[ios android].include?(params[:platform])
    defaults = { context: "default", presentation: "default", pull_to_refresh_enabled: false }
    defaults[:uri] = "hotwire://fragment/web" if params[:platform] == "android"
    authentication = { context: "modal" }
    authentication[:uri] = "hotwire://fragment/web/modal/sheet" if params[:platform] == "android"
    response.headers["Cache-Control"] = "public, max-age=300"
    render json: {
      settings: { schema_version: 1, live_execution: false, synthetic_sandbox: true },
      rules: [
        { patterns: [".*"], properties: defaults },
        { patterns: ["^/users/(sign_in|sign_up|password/new)$"], properties: authentication }
      ]
    }
  end
end
