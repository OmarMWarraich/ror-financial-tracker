class PortfolioDemosController < ApplicationController
  skip_before_action :authenticate_user!, only: :show

  def show
    @scenario = params.fetch(:scenario, "complete")
    raise ActionController::BadRequest, "Unknown demo scenario" unless DemoPortfolio::SCENARIOS.key?(@scenario)

    @portfolio = DemoPortfolio.build(scenario: @scenario)
  end
end
