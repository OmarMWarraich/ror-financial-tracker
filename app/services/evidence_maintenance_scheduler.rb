require "fileutils"

class EvidenceMaintenanceScheduler
  INTERVAL = 300
  HEARTBEAT = Rails.root.join("tmp", "evidence-maintenance-heartbeat")
  class EnqueueError < StandardError; end

  def initialize(heartbeat: HEARTBEAT)
    @heartbeat = heartbeat
  end

  def tick
    Research::Agent::Lifecycle.recover!
    job = ExpireEquiblesEvidenceJob.perform_later
    raise EnqueueError, "Evidence retention maintenance was not enqueued" unless job && job.successfully_enqueued?
    disposal = ResearchDisposalJob.perform_later
    raise EnqueueError, "Research disposal maintenance was not enqueued" unless disposal && disposal.successfully_enqueued?
    FileUtils.touch(@heartbeat)
  end

  def run
    loop do
      tick
      sleep INTERVAL
    end
  end
end
