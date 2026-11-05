require "test_helper"

class ExpireEquiblesEvidenceJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    @connection = EquiblesConnection.create!(
      user: @user, snapshot: { "provider" => "equibles", "price" => "100",
                              "entitlement" => { "retention_seconds" => 3600 } },
      last_success_at: 2.hours.ago
    )
    @settings = {
      "approval_reference" => "offline-job-test", "subscription_verified" => true,
      "paid_quotes" => true, "automated_read" => true, "private_display" => true,
      "cache_storage" => true, "daily_request_budget" => 10,
      "retention_seconds" => 3600, "freshness_seconds" => 900
    }
  end

  test "maintenance job has no private arguments or provider requests" do
    assert_enqueued_with(job: ExpireEquiblesEvidenceJob, args: [], queue: "maintenance") do
      ExpireEquiblesEvidenceJob.perform_later
    end
    Net::HTTP.stub(:start, ->(*) { flunk "Retention must not request a provider" }) do
      ExpireEquiblesEvidenceJob.perform_now
      ExpireEquiblesEvidenceJob.perform_now
    end
    assert_empty @connection.reload.snapshot
    assert_nil @connection.last_attempt_at
    assert_equal 0, @connection.requests_used
  end

  test "fresh permitted evidence survives while expired evidence is purged idempotently" do
    @connection.update!(last_success_at: Time.current)
    with_approval do
      ExpireEquiblesEvidenceJob.perform_now
      assert_equal "100", @connection.reload.snapshot["price"]
      @connection.update!(last_success_at: 2.hours.ago)
      2.times { ExpireEquiblesEvidenceJob.perform_now }
      assert_empty @connection.reload.snapshot
    end
  end

  test "cleanup rechecks current approval and original retention deadline" do
    @connection.update!(last_success_at: Time.current)
    ExpireEquiblesEvidenceJob.perform_now
    assert_empty @connection.reload.snapshot

    @connection.update!(snapshot: { "price" => "200",
                                   "entitlement" => { "retention_seconds" => 60 } },
                        last_success_at: 2.minutes.ago)
    with_approval { ExpireEquiblesEvidenceJob.perform_now }
    assert_empty @connection.reload.snapshot
  end

  private

  def with_approval
    settings = { "verified_users" => { @user.id.to_s => @settings } }
    Rails.application.stub(:config_for, settings) { yield }
  end
end
