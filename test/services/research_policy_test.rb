require "test_helper"

class ResearchPolicyTest < ActiveSupport::TestCase
  setup do
    @owner = users(:one)
    @space = @owner.research_embedding_spaces.create!(
      provider: "openai", model: "text-embedding-3-small", model_version: "text-embedding-3-small",
      preprocessing_version: Research::Chunker::PREPROCESSING, chunker_version: Research::Chunker::VERSION
    )
    @request = ResearchIngestion.new(user: @owner, space: @space, provider: "equibles",
      source_kind: "earnings_transcript", listing_identity: "US:MSFT", fiscal_year: 2026,
      fiscal_quarter: 3, request_key: "original-policy-test")
    @settings = Research::Policy::REQUIRED.index_with { true }.merge(
      "approval_reference" => "original-test-only-approval", "source_kinds" => ["earnings_transcript"],
      "listings" => ["US:MSFT"], "retention_seconds" => 3600, "backup_retention_seconds" => 3600, "freshness_seconds" => 600,
      "daily_source_requests" => 3, "expires_at" => (Time.current + 1.day).iso8601
    )
  end

  test "private ingestion defaults disabled and quote approval cannot authorize it" do
    assert_equal "research_permission_required", assert_raises(Research::Error) {
      Research::Policy.new(@owner).check!(@request)
    }.code
    assert_raises(Research::Error) do
      Research::Policy.new(@owner, configuration: { verified_users: { @owner.id => @settings } }).check!(@request)
    end
  end

  test "each permission exact listing model and expiry is required separately" do
    assert policy.check!(@request)
    Research::Policy::REQUIRED.each do |name|
      assert_raises(Research::Error) { policy(@settings.merge(name => false)).check!(@request) }
    end
    [{ "listings" => ["US:OTHER"] }, { "source_kinds" => ["filing"] }, { "retention_seconds" => 0 },
     { "expires_at" => Time.current.iso8601 }, { "expires_at" => "unknown" },
     { "daily_source_requests" => 31 }, { "freshness_seconds" => 3601 },
     { "backup_retention_seconds" => nil }, { "backup_retention_seconds" => 0 },
     { "backup_retention_seconds" => 3601 }, { "backup_retention_seconds" => 604_801 }].each do |changes|
      assert_raises(Research::Error) { policy(@settings.merge(changes)).check!(@request) }
    end
    assert_not policy.history?(@request)
    assert policy(@settings.merge("historical_storage" => true)).history?(@request)
    @space.update!(state: "retired")
    assert_equal "embedding_space_not_allowlisted", assert_raises(Research::Error) { policy.check!(@request) }.code
  end

  private

  def policy(settings = @settings)
    Research::Policy.new(@owner, configuration: { "approved_owners" => { @owner.id.to_s => settings } })
  end
end
