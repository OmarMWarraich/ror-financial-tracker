class PortfolioDemosController < ApplicationController
  skip_before_action :authenticate_user!, only: :show

  def show
    @scenario = params.fetch(:scenario, "complete")
    raise ActionController::BadRequest, "Unknown demo scenario" unless DemoPortfolio::SCENARIOS.key?(@scenario)

    response.headers["Cache-Control"] = "no-store"
    @evidence_state = DemoPortfolio::STATES[@scenario]
    @portfolio = DemoPortfolio.build(scenario: @scenario) unless @evidence_state
  end
end
