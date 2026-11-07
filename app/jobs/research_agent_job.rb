class ResearchAgentJob
  include Sidekiq::Job
  sidekiq_options queue: "research", retry: false, backtrace: false

  def perform(run_id)
    run = ResearchAgentRun.find_by(id: run_id)
    unless run
      Rails.logger.warn("Research run #{run_id} rejected code=request_missing")
      return
    end
    Research::Agent::Execution.call(run)
  rescue Research::Error => error
    Rails.logger.warn("Research run #{run_id} rejected code=#{error.code}")
    if error.code == "agent_concurrency_limit" && run.reload.state == "queued"
      begin
        Research::Agent::Lifecycle.enqueue!(run, wait: 15)
      rescue Research::Error => queue_error
        Research::Agent::Lifecycle.terminal!(run, state: "failed", code: queue_error.code)
      end
    end
  end
end
