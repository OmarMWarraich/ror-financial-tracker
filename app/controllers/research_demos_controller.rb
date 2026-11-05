class ResearchDemosController < ApplicationController
  skip_before_action :authenticate_user!, only: :show

  def show
    @scenario = params.fetch(:scenario, "valid")
    raise ActionController::BadRequest, "Unknown research scenario" unless SyntheticResearch::SCENARIOS.key?(@scenario)
    response.headers["Cache-Control"] = "no-store"
    @insight, @evidence, budget = SyntheticResearch.fixture(@scenario)
    @result = SyntheticResearch.evaluate(@insight, evidence: @evidence, now: SyntheticResearch::CLOCK,
                                        budget_remaining: budget)
  end
end
