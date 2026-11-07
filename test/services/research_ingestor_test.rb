require "test_helper"

class ResearchIngestorTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @owners = []
    @owner = create_owner
    @space = create_space(@owner)
    @request = create_request
  end

  teardown do
    @owners.each do |owner|
      owner.with_lock do
        ResearchEmbeddingAttempt.where(user: owner).delete_all
        ResearchIngestion.where(user: owner).delete_all
        ResearchDocument.where(user: owner).update_all(current_revision_id: nil)
        ResearchEmbedding.where(user: owner).delete_all
        ResearchPassage.where(user: owner).delete_all
        ResearchRevision.where(user: owner).delete_all
        ResearchDocument.where(user: owner).delete_all
        ResearchEmbeddingSpace.where(user: owner).delete_all
      end
      owner.destroy!
    end
  end

  test "original public fixture indexes server-side and duplicate jobs make no more calls" do
    source = Source.new
    embedder = Embeddings.new
    ingest(@request, source: source, embedder: embedder)
    assert_equal "ready", @request.reload.state
    assert_equal 1, source.calls
    assert_equal 1, embedder.calls
    assert_equal 0, @request.source_requests
    assert_equal "ready", @request.document.current_revision.index_state
    assert_equal 2, @space.embeddings.count
    assert_equal 0, @request.embedding_attempts.sum(:actual_cost_nanos)
    ingest(@request, source: source, embedder: embedder)
    assert_equal 1, source.calls
    assert_equal 1, embedder.calls
    @space.activate!
    assert_equal 2, @space.nearest(@space.embeddings.first.embedding).size
    assert_not source.transaction_open
    assert_not embedder.transaction_open
  end

  test "enqueue idempotency is owner scoped and rejects altered or injected state" do
    attributes = @request.attributes.symbolize_keys.slice(:request_key, :provider, :source_kind,
      :listing_identity, :fiscal_year, :fiscal_quarter, :fixture_version)
    assert_equal @request.id, Research::Ingestor.enqueue!(user: @owner, space: @space, **attributes).id
    assert_raises(Research::Error) {
      Research::Ingestor.enqueue!(user: @owner, space: @space, **attributes.merge(fiscal_quarter: 2))
    }
    assert_raises(Research::Error) {
      Research::Ingestor.enqueue!(user: @owner, space: @space, **attributes.merge(state: "ready"))
    }
    other = create_owner
    other_space = create_space(other)
    assert_not_equal @request.id, Research::Ingestor.enqueue!(user: other, space: other_space, **attributes).id
    assert_raises(ActiveRecord::RecordInvalid) {
      Research::Ingestor.enqueue!(user: other, space: @space, **attributes.merge(request_key: "different"))
    }
  end

  test "source content deduplicates across distinct fetch requests without extending retention" do
    ingest(@request)
    first = @request.reload.document.current_revision
    second = create_request
    ingest(second)
    assert_equal first.id, second.reload.document.current_revision_id
    assert_equal 1, second.document.revisions.count
    assert_equal first.received_at, second.document.current_revision.received_at
    assert_equal first.expires_at, second.document.current_revision.expires_at
    assert_equal 0, second.embedding_attempts.count
  end

  test "partial embeddings remain invisible and explicit resume skips settled batches and fetch" do
    source = Source.new(parts: 8)
    embedder = Embeddings.new(fail_at: 2, actual_tokens: 0)
    ingest(@request, source: source, embedder: embedder)
    assert_equal "failed", @request.reload.state
    assert_equal 4, @space.embeddings.count
    assert_nil @request.document.current_revision_id
    assert_equal "failed", @request.document.revisions.first.index_state
    assert_empty ResearchPassage.eligible_for(@space, at: Time.current)
    @request.resume!
    ingest(@request, source: source, embedder: embedder)
    assert_equal "ready", @request.reload.state
    assert_equal 8, @space.embeddings.count
    assert_equal 1, source.calls
    assert_equal 3, embedder.calls
  end

  test "uncertain billing is retained and never automatically replayed" do
    source = Source.new
    embedder = Embeddings.new(fail_at: 1)
    ingest(@request, source: source, embedder: embedder)
    receipt = @request.embedding_attempts.first
    assert_equal "uncertain", receipt.state
    assert_nil receipt.actual_tokens
    assert_equal "uncertain_usage_requires_review", assert_raises(Research::Error) { @request.resume! }.code
    assert_raises(Research::Error) { ingest(@request, source: source, embedder: embedder) }
    assert_equal 1, embedder.calls
    different_key = create_request
    ingest(different_key, source: source, embedder: embedder)
    assert_equal "uncertain_usage_requires_review", different_key.reload.error_code
    assert_equal 1, embedder.calls
  end

  test "a newer source fences a late job and only the corrected revision is current" do
    newer = create_request(fixture_version: "v2")
    embedder = Embeddings.new(callback: -> { ingest(newer) })
    ingest(@request, embedder: embedder)
    assert_equal "failed", @request.reload.state
    assert_equal "source_superseded", @request.error_code
    assert_equal "ready", newer.reload.state
    assert_includes newer.document.current_revision.content, "125"
    assert_equal 2, @space.embeddings.count
    @request.resume!
    ingest(@request)
    assert_equal "source_superseded", @request.reload.error_code
  end

  test "corrections preserve immutable history while current retrieval excludes superseded revisions" do
    ingest(@request)
    previous = @request.reload.document.current_revision
    @space.activate!
    newer = create_request(fixture_version: "v2")
    ingest(newer)
    assert previous.reload.superseded_at
    assert_includes previous.content, "120"
    assert_equal 2, newer.reload.document.revisions.count
    nearest = @space.nearest(@space.embeddings.first.embedding)
    assert_equal [newer.document.current_revision_id], nearest.map { |row| row.passage.revision_id }.uniq
  end

  test "an accepted correction cannot fall back to the earlier current revision if indexing fails" do
    ingest(@request)
    previous = @request.reload.document.current_revision
    @space.activate!
    corrected = create_request(fixture_version: "v2")
    ingest(corrected, embedder: Embeddings.new(fail_at: 1, actual_tokens: 0))
    assert_equal "failed", corrected.reload.state
    assert previous.reload.superseded_at
    assert_nil corrected.document.current_revision_id
    assert_empty @space.nearest(@space.embeddings.first.embedding)
    corrected.resume!
    ingest(corrected)
    assert_equal "ready", corrected.reload.state
    assert_equal corrected.source_revision, corrected.document.current_revision.source_revision
  end

  test "revocation expiry and deletion during embedding cannot publish or recreate source" do
    [:revoked, :expired, :deleted].each do |mode|
      request = create_request
      callback = lambda do
        document = request.reload.document
        @owner.with_lock do
          case mode
          when :revoked then document.update!(revoked_at: Time.current)
          when :expired then document.update!(rights_expires_at: Time.current)
          when :deleted
            request.update!(document_id: nil)
            ResearchPassage.where(revision_id: document.revisions.select(:id)).delete_all
            ResearchRevision.where(document_id: document.id).delete_all
            document.destroy!
          end
        end
      end
      ingest(request, embedder: Embeddings.new(callback: callback))
      assert_equal "failed", request.reload.state
      assert_equal 0, @space.embeddings.count
      assert_equal "settled", request.embedding_attempts.first.state
      request.resume!
      ingest(request)
      assert_equal "failed", request.reload.state
      # Each iteration uses a new logical source so a prior revoked document cannot be reused.
      @owner.with_lock do
        ResearchIngestion.where(user: @owner).update_all(document_id: nil)
        ResearchPassage.where(user: @owner).delete_all
        ResearchRevision.where(user: @owner).delete_all
        ResearchDocument.where(user: @owner).delete_all
      end
    end
  end

  test "private permissions quota credentials and historical storage are enforced with original fakes only" do
    private_setup
    source = Source.new
    ingest(@private_request, source: source, embedder: Embeddings.new)
    assert_equal "research_permission_required", @private_request.reload.error_code
    assert_equal 0, source.calls
    assert_equal 0, @connection.reload.requests_used
    @private_request.resume!
    run_private(@private_request, source: source)
    assert_equal "ready", @private_request.reload.state
    assert_equal 1, @connection.reload.requests_used
    assert_operator @private_request.embedding_attempts.first.actual_cost_nanos, :>, 0
    previous = @private_request.document.current_revision
    newer = create_request(provider: "equibles", space: @private_space, listing_identity: "US:TEST", fixture_version: nil)
    run_private(newer, source: Source.new(version: "v2"))
    assert_equal "ready", newer.reload.state
    assert_not ResearchRevision.exists?(previous.id)
    assert_equal 1, newer.document.revisions.count
    limited = create_request(provider: "equibles", space: @private_space, listing_identity: "US:TEST", fixture_version: nil)
    @connection.update!(requests_used: 3, quota_date: Time.current.utc.to_date)
    run_private(limited, source: Source.new)
    assert_equal "source_request_budget_exceeded", limited.reload.error_code
    assert_equal 3, @connection.reload.requests_used
  end

  test "permission and owner-key changes are rechecked after each external call" do
    private_setup
    run_private(@private_request, embedder: Embeddings.new(callback: -> { @settings["openai_processing"] = false }))
    assert_equal "research_permission_required", @private_request.reload.error_code
    assert_equal 0, @private_space.embeddings.count
    assert @private_request.document.revoked_at
    @settings["openai_processing"] = true
    @owner.with_lock do
      @private_request.document.update!(revoked_at: nil)
    end
    @private_request.resume!
    run_private(@private_request, embedder: Embeddings.new(callback: -> { @connection.update!(api_key: "original-replacement-key") }))
    assert_equal "source_credentials_changed", @private_request.reload.error_code
    assert_equal 0, @private_space.embeddings.count
  end

  test "concurrent reservations cannot exceed the exact daily token threshold" do
    6.times { |index| ResearchEmbeddingAttempt.reserve!(@request, tokens: 3000, batch_key: "seed-#{index}", paid: false) }
    outcomes = 2.times.map do |index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          begin
            ResearchEmbeddingAttempt.reserve!(@request, tokens: 2000, batch_key: "race-#{index}", paid: false)
            "reserved"
          rescue Research::Error => error
            error.code
          end
        end
      end
    end.map(&:value)
    assert_equal ["embedding_budget_exceeded", "reserved"], outcomes.sort
    assert_equal 20_000, @request.embedding_attempts.sum(:reserved_tokens)
  end

  test "the application dollar ceiling covers other owners and retains uncertain reservations" do
    2.times do
      owner = create_owner
      request = create_request(user: owner, space: create_space(owner))
      ResearchEmbeddingAttempt.create!(user: owner, ingestion: request, generation: 0, batch_key: "original-global-budget",
        budget_date: Time.current.utc.to_date, state: "uncertain", reserved_tokens: 1, reserved_cost_nanos: 500_000_000)
    end
    assert_equal "embedding_budget_exceeded", assert_raises(Research::Error) {
      ResearchEmbeddingAttempt.reserve!(@request, tokens: 1, batch_key: "global-cap", paid: true)
    }.code
  end

  private

  def create_owner
    User.create!(email: "original-ingestion-#{SecureRandom.hex(8)}@example.test", password: "original-test-password").tap {
      |user| @owners << user
    }
  end

  def create_space(owner, provider: "synthetic")
    owner.research_embedding_spaces.create!(provider: provider,
      model: provider == "synthetic" ? "fixture-1536" : "text-embedding-3-small",
      model_version: provider == "synthetic" ? "sha256-v1" : "text-embedding-3-small",
      preprocessing_version: Research::Chunker::PREPROCESSING, chunker_version: Research::Chunker::VERSION)
  end

  def create_request(**overrides)
    ResearchIngestion.create!({ user: @owner, space: @space, provider: "synthetic",
      source_kind: "earnings_transcript", listing_identity: "SYNTH:ALPHA", fiscal_year: 2026,
      fiscal_quarter: 3, fixture_version: "v1", request_key: SecureRandom.uuid }.merge(overrides))
  end

  def ingest(request, **options)
    Research::Ingestor.new(request, **options).call
  end

  def private_setup
    @private_space = create_space(@owner, provider: "openai")
    @connection = @owner.create_equibles_connection!(api_key: "original-equibles-dummy-key")
    @private_request = create_request(provider: "equibles", space: @private_space, listing_identity: "US:TEST", fixture_version: nil)
    @settings = Research::Policy::REQUIRED.index_with { true }.merge("approval_reference" => "original-offline-approval",
      "source_kinds" => ["earnings_transcript"], "listings" => ["US:TEST"], "retention_seconds" => 3600,
      "freshness_seconds" => 600, "daily_source_requests" => 3, "expires_at" => (Time.current + 1.day).iso8601)
  end

  def run_private(request, source: Source.new, embedder: Embeddings.new)
    factory = ->(user) { Research::Policy.new(user, configuration: { approved_owners: { user.id.to_s => @settings } }) }
    ingest(request, policy_factory: factory, source: source, embedder: embedder)
  end

  class Source
    attr_reader :calls, :transaction_open
    def initialize(parts: nil, version: nil)
      @calls = 0
      @parts = parts
      @version = version
    end
    def call(request, before_request:, api_key:)
      before_request.call if request.provider == "equibles"
      @transaction_open = ApplicationRecord.connection.transaction_open?
      @calls += 1
      fixture = request.dup
      fixture.fixture_version = @version || request.fixture_version || "v1"
      result = Research::SyntheticSource.new.call(fixture)
      result[:metadata]["listing_identity"] = request.listing_identity
      if @parts
        result[:parts] = Array.new(@parts) { |index| { "text" => "Original demonstration statement #{index}.", "turn_index" => index } }
      end
      result
    end
  end

  class Embeddings
    attr_reader :calls, :transaction_open
    def initialize(fail_at: nil, actual_tokens: nil, callback: nil)
      @calls = 0
      @fail_at = fail_at
      @actual_tokens = actual_tokens
      @callback = callback
    end
    def prepare!; end
    def call(batch, timeout:, idempotency_key:)
      @transaction_open = ApplicationRecord.connection.transaction_open?
      @calls += 1
      @callback&.call
      raise Research::Error.new("embedding_provider_error", actual_tokens: @actual_tokens) if @calls == @fail_at
      Research::Embedder::Result.new(tokens: batch.sum(&:token_count),
        vectors: batch.map { Array.new(1536, 0.0).tap { |values| values[0] = 1.0 } })
    end
  end
end
