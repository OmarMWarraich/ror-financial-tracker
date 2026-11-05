require "test_helper"
require "tempfile"

class EvidenceMaintenanceSchedulerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "a successful tick enqueues only argument-free retention then updates its heartbeat" do
    Tempfile.create("retention-heartbeat") do |file|
      scheduler = EvidenceMaintenanceScheduler.new(heartbeat: file.path)
      assert_enqueued_with(job: ExpireEquiblesEvidenceJob, args: [], queue: "maintenance") { scheduler.tick }
      assert File.mtime(file.path) >= 5.seconds.ago
    end
  end

  test "failed enqueue is explicit and cannot produce a healthy heartbeat" do
    Tempfile.create("retention-heartbeat") do |file|
      old = Time.at(1)
      File.utime(old, old, file.path)
      ExpireEquiblesEvidenceJob.stub(:perform_later, false) do
        assert_raises(EvidenceMaintenanceScheduler::EnqueueError) do
          EvidenceMaintenanceScheduler.new(heartbeat: file.path).tick
        end
      end
      assert_equal old, File.mtime(file.path)
    end
  end
end
