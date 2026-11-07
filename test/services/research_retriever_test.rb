require "test_helper"

class ResearchRetrieverTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @owners = []
    @owner = new_owner
    @now = Time.current
    @space = new_space(@owner)
    @part = evidence("Original Alpha revenue grew; cloud margins improved.")
    @space.activate!
    @embedder = Embeddings.new
  end

  teardown do
    @owners.each do |owner|
      owner.with_lock do
        ResearchEmbeddingAttempt.where(user: owner).delete_all
        ResearchRetrieval.where(user: owner).delete_all
        ResearchIngestion.where(user: owner).delete_all
        ResearchDocument.where(user: owner).update_all(current_revision_id: nil)
        ResearchEmbedding.where(user: owner).delete_all
        ResearchPassage.where(user: owner).delete_all
        ResearchRevision.where(user: owner).delete_all
        ResearchDocument.where(user: owner).delete_all
        ResearchEmbeddingSpace.where(user: owner).delete_all
      end
      owner.equibles_connection&.destroy!
      owner.destroy!
    end
  end

  test "keyword baseline and hybrid return bounded attributed context and shared query receipts" do
    lexical = retrieve(strategy: "keyword")
    assert_equal "ready", lexical.status
    assert_equal 0, @embedder.calls
    hybrid = retrieve
    data = JSON.parse(hybrid.context_json)
    assert_equal @part.id, data["sources"].first["passage_id"]
    assert_equal "SYNTH:ALPHA", data["sources"].first["listing_identity"]
    assert_equal "Q3", data["sources"].first["fiscal_period"]
    assert_equal 8, data["sources"].first["dates"].size
    assert_equal "original_fixture", data["sources"].first["dates"]["known_at"]["basis"]
    assert_equal @part.revision.source_metadata["provider_event_id"], data["sources"].first["provider_event_id"]
    assert data["sources"].first["synthetic"]
    assert_equal 1, @embedder.calls
    assert_not @embedder.transaction_open
    assert_nil hybrid.request.embedding_attempts.first.ingestion_id
    assert_equal hybrid.request.id, hybrid.request.embedding_attempts.first.retrieval_id
    assert_equal "settled", hybrid.request.embedding_attempts.first.state
    assert_operator Research::Chunker.new.tokens(hybrid.context_json), :<=, 4000
    assert_operator hybrid.context_json.bytesize, :<=, Research::Retriever::MAX_CONTEXT_BYTES
  end

  test "keyword remains the default until hybrid quality acceptance is established" do
    result = Research::Retriever.new(user: @owner, space: @space, query: "revenue", request_key: SecureRandom.uuid,
      listing_identity: "SYNTH:ALPHA", fiscal_year: 2026, fiscal_period: "Q3", embedder: @embedder).call
    assert_equal "ready", result.status
    assert_equal "keyword", result.request.selectors["strategy"]
    assert_equal 0, @embedder.calls
  end

  test "hard owner instrument period rights and deletion filters precede both rankings" do
    other = new_owner
    evidence("Revenue revenue revenue", owner: other, space: new_space(other))
    evidence("Revenue revenue revenue", listing: "SYNTH:OTHER")
    evidence("Revenue revenue revenue", period: "Q2")
    evidence("Revenue revenue revenue", instrument: "wrong-instrument")
    evidence("Revenue revenue revenue", approval: "not-approved")
    revoked = evidence("Revenue revenue revenue")
    revoked.revision.document.update!(revoked_at: @now)
    expired = evidence("Revenue revenue revenue")
    expired.revision.update!(expires_at: Time.current, fresh_until: nil)
    pending = evidence("Revenue revenue revenue")
    pending.revision.update!(index_state: "pending")
    %w[keyword hybrid].each do |strategy|
      result = retrieve(strategy: strategy)
      assert_equal [@part.id], JSON.parse(result.context_json)["sources"].map { |source| source["passage_id"] }
    end
  end

  test "unknown publication is labelled current evidence but cannot prove historical availability" do
    @part.revision.update!(known_at: nil, published_at: nil)
    current = retrieve
    source = JSON.parse(current.context_json)["sources"].first
    assert source["uncertainty"]["publication_unknown"]
    assert source["uncertainty"]["knowability_unknown"]
    assert_equal "unknown", source["dates"]["known_at"]["confidence"]
    historical = retrieve(mode: "as_of", as_of: @now - 1.day)
    assert_equal "no_evidence", historical.status
    assert_raises(Research::Error) { historical.context_json }
  end

  test "as-of selects the then-known version and permits later download only with confirmed provenance" do
    original = @part.revision
    original.update!(known_at: @now - 5.days, published_at: @now - 5.days, superseded_at: @now)
    newer = evidence("Original corrected Alpha revenue was lower.", document: original.document,
                     known: @now - 1.day, received: @now - 1.hour)
    earlier = retrieve(mode: "as_of", as_of: @now - 3.days, strategy: "keyword")
    assert_equal [original.id], JSON.parse(earlier.context_json)["sources"].map { |source| source["revision_id"] }
    later = retrieve(mode: "as_of", as_of: @now, strategy: "keyword")
    assert_equal [newer.revision_id], JSON.parse(later.context_json)["sources"].map { |source| source["revision_id"] }
    assert_operator original.received_at, :>, @now - 3.days
    ResearchRevision.where(id: original.id).update_all(temporal_metadata: {})
    assert_equal "no_evidence", retrieve(mode: "as_of", as_of: @now - 3.days).status
  end

  test "unknown or same-time restatement timelines cannot silently select an older revision" do
    original = @part.revision
    evidence("Original revised revenue", document: original.document, known: original.known_at)
    assert_equal "no_evidence", retrieve(mode: "as_of", as_of: @now).status
    ResearchRevision.where(document_id: original.document_id).where.not(id: original.id).update_all(known_at: nil)
    assert_equal "no_evidence", retrieve(mode: "as_of", as_of: @now - 1.day).status
  end

  test "future event publication and knowability are never rescued by later receipt" do
    %i[event_at published_at known_at].each do |field|
      revision = @part.revision
      before = revision.public_send(field)
      revision.update!(field => @now + 1.day)
      assert_equal "no_evidence", retrieve.status
      revision.update!(field => before)
    end
  end

  test "stale-only and irrelevant evidence do not dispatch or fabricate fallback context" do
    @part.revision.update!(fresh_until: @now - 1.second)
    result = retrieve
    assert_equal "stale_only", result.status
    assert_equal "evidence_requires_recheck", result.reason
    assert_equal 0, @embedder.calls
    assert ResearchPassage.exists?(@part.id)
    @part.revision.update!(fresh_until: @now + 1.hour)
    assert_equal "no_evidence", retrieve(query: "unrelated geology", embedder: Embeddings.new(position: 1)).status
  end

  test "count exact serialized token and byte budgets include provenance not just passage text" do
    9.times { |index| evidence("Original revenue account #{index} expanded cloud margins.") }
    result = retrieve(limit: 2, context_tokens: 1800)
    assert_operator JSON.parse(result.context_json)["sources"].size, :<=, 2
    assert_operator Research::Chunker.new.tokens(result.context_json), :<=, 1800
    none = retrieve(context_tokens: 1)
    assert_equal "no_evidence", none.status
    assert_equal "context_budget_exceeded", none.reason
    assert_raises(Research::Error) { retrieve(limit: 7) }
    assert_raises(Research::Error) { retrieve(context_tokens: 6001) }
    assert_raises(Research::Error) { retrieve(query: "word " * 501) }
    assert_raises(Research::Error) { retrieve(query: "api_key: original-demo-secret") }
    assert_raises(Research::Error) { retrieve(mode: "as_of", as_of: "2026-10-28") }
    assert_raises(Research::Error) { retrieve(mode: "as_of", as_of: @now + 1.day) }
  end

  test "keyword stemming and equal-content deduplication do not repeat source context" do
    text = "Original Alpha revenues expanded."
    first = evidence(text)
    evidence(text)
    result = retrieve(strategy: "keyword", query: "revenue")
    ids = JSON.parse(result.context_json)["sources"].map { |source| source["passage_id"] }
    assert_includes ids, first.id
    assert_equal 2, ids.size
    assert_equal "no_evidence", retrieve(strategy: "keyword", query: "'; DROP TABLE research_passages; --").status
    assert ResearchPassage.exists?(@part.id)
  end

  test "source expiry rights and revision changes invalidate already selected context" do
    result = retrieve
    document = @part.revision.document
    document.update!(rights_expires_at: Time.current)
    assert_raises(Research::Error) { result.context_json }
    document.update!(rights_expires_at: @now + 30.days)
    @part.revision.update!(revoked_at: @now)
    assert_raises(Research::Error) { result.context_json }
    @part.revision.update!(revoked_at: nil)
    evidence("Original corrected revenue.", document: document, known: @now - 1.hour)
    assert_raises(Research::Error) { result.context_json }
  end

  test "current unknown availability can complete storage cutover without enabling historical primitive queries" do
    @space.update!(state: "building")
    @part.revision.update!(known_at: nil, published_at: nil)
    @space.activate!
    assert_equal "active", @space.state
    assert_empty @space.nearest(vector(0))
    assert_equal "ready", retrieve.status
  end

  test "source revalidation refreshes relevance without renewing receipt knowability or deletion" do
    request = @owner.research_ingestions.create!(space: @space, request_key: SecureRandom.uuid,
      provider: "synthetic", source_kind: "earnings_brief", listing_identity: "SYNTH:ALPHA",
      fiscal_year: 2026, fiscal_quarter: 3, fixture_version: "v1")
    Research::Ingestor.new(request).call
    revision = request.reload.document.current_revision
    original = revision.attributes.slice("received_at", "known_at", "expires_at", "source_revision")
    old_verification = revision.verified_at
    travel_to(Time.current + 2.days) do
      again = request.dup
      again.request_key = SecureRandom.uuid
      again.state = "pending"
      again.document_generation = nil
      again.document_id = nil
      again.source_revision = nil
      again.save!
      Research::Ingestor.new(again).call
      assert_equal revision.id, again.reload.document.current_revision_id
      assert_equal original, revision.reload.attributes.slice("received_at", "known_at", "expires_at", "source_revision")
      assert_operator revision.verified_at, :>, old_verification
      assert_operator revision.fresh_until, :>, Time.current
      assert_equal 1, request.document.revisions.count
    end
  end

  test "query receipt SQL cannot cross owners or masquerade as both ingestion and retrieval" do
    result = retrieve
    other = new_owner
    other_space = new_space(other)
    assert_raises(ActiveRecord::InvalidForeignKey) {
      ResearchRetrieval.where(id: result.request.id).update_all(space_id: other_space.id)
    }
    receipt = result.request.embedding_attempts.first
    assert_raises(ActiveRecord::InvalidForeignKey) {
      ResearchEmbeddingAttempt.where(id: receipt.id).update_all(user_id: other.id)
    }
    assert_raises(ActiveRecord::StatementInvalid) {
      ResearchEmbeddingAttempt.where(id: receipt.id).update_all(retrieval_id: nil)
    }
    assert_raises(Research::Error) { retrieve(space: other_space) }
  end

  test "latest resolves metadata before selection and never relabels older approved briefs" do
    @part.revision.update!(fresh_until: @now - 1.hour)
    old = evidence("Original Alpha revenue brief from an older quarter.", kind: "earnings_brief", period: "Q2")
    result = retrieve(mode: "latest_earnings", fiscal_year: nil, fiscal_period: nil)
    source = JSON.parse(result.context_json)["sources"].first
    assert_equal @part.id, source["passage_id"]
    assert_equal "earnings_transcript", source["source_kind"]
    assert_not_equal old.id, source["passage_id"]
    exact = evidence("Original Alpha revenue latest-event brief.", kind: "earnings_brief")
    preferred = retrieve(mode: "latest_earnings", fiscal_year: nil, fiscal_period: nil)
    assert_equal [exact.id], JSON.parse(preferred.context_json)["sources"].map { |entry| entry["passage_id"] }
    @part.revision.document.update!(revoked_at: @now)
    exact.revision.document.update!(revoked_at: @now)
    assert_equal "no_evidence", retrieve(mode: "latest_earnings", fiscal_year: nil, fiscal_period: nil).status
  end

  test "missing authoritative latest event reports absence instead of corpus-derived latest" do
    latest = Object.new
    def latest.call(**)
      { "reason" => "latest_event_unconfirmed_or_unavailable", "observed_at" => Time.current.iso8601 }
    end
    result = retrieve(mode: "latest_earnings", fiscal_year: nil, fiscal_period: nil, latest_source: latest)
    assert_equal "no_evidence", result.status
    assert_equal "latest_event_unconfirmed_or_unavailable", result.reason
    assert_equal 0, @embedder.calls
  end

  test "idempotency is owner scoped and never redispatches uncertain query work under a new key" do
    first = retrieve(request_key: "original-query")
    again = retrieve(request_key: "original-query")
    assert_equal first.request.id, again.request.id
    assert_equal 1, @embedder.calls
    assert_raises(Research::Error) { retrieve(request_key: "original-query", query: "margin") }
    uncertain = Embeddings.new(fail: true)
    assert_raises(Research::Error) { retrieve(query: "revenue uncertainty", embedder: uncertain) }
    receipt = ResearchRetrieval.where(user: @owner).order(:id).last.embedding_attempts.first
    assert_equal "uncertain", receipt.state
    assert_nil receipt.actual_tokens
    assert_equal "uncertain_usage_requires_review", assert_raises(Research::Error) {
      retrieve(query: "revenue uncertainty", embedder: uncertain)
    }.code
    assert_equal 1, uncertain.calls
  end

  test "query embedding consumes the same owner UTC allowance as ingestion" do
    ingestion = @owner.research_ingestions.create!(space: @space, request_key: SecureRandom.uuid,
      provider: "synthetic", source_kind: "earnings_transcript", listing_identity: "SYNTH:ALPHA",
      fiscal_year: 2026, fiscal_quarter: 3, fixture_version: "v1")
    ([3200] * 6 + [800]).each_with_index do |tokens, index|
      ResearchEmbeddingAttempt.create!(user: @owner, ingestion: ingestion, batch_key: "original-budget-#{index}",
        generation: 0, budget_date: Time.current.utc.to_date, reserved_tokens: tokens, reserved_cost_nanos: 0)
    end
    assert_equal "embedding_budget_exceeded", assert_raises(Research::Error) { retrieve }.code
    assert_equal 0, @embedder.calls
  end

  test "preflight and postflight guards prevent revoked changed expired or cut-over evidence publication" do
    result = retrieve
    @part.revision.document.update!(revoked_at: @now)
    calls = 0
    assert_raises(Research::Error) { result.dispatch!(publisher: ->(_) { flunk }) { calls += 1 } }
    assert_equal 0, calls
    @part.revision.document.update!(revoked_at: nil)
    published = false
    assert_raises(Research::Error) do
      result.dispatch!(publisher: ->(_) { published = true }) do |context|
        assert_not ApplicationRecord.connection.transaction_open?
        assert JSON.parse(context)["sources"].present?
        @part.revision.update!(expires_at: Time.current, fresh_until: nil)
        "Original fake model output"
      end
    end
    assert_not published
    @part.revision.update!(expires_at: @now + 7.days)
    @space.update!(state: "retired")
    assert_raises(Research::Error) { result.context_json }
  end

  test "valid dispatch publishes only under revalidated database guards" do
    result = retrieve
    output = result.dispatch!(publisher: ->(response) {
      assert ApplicationRecord.connection.transaction_open?
      response
    }) { "Original local response" }
    assert_equal "Original local response", output
    @part.revision.document.update!(ingestion_generation: 99)
    assert_equal "evidence_changed_or_disallowed", assert_raises(Research::Error) { result.context_json }.code
  end

  test "private defaults and current permission removal cannot be bypassed by cached selection" do
    private_space = new_space(@owner, provider: "openai")
    @space.update!(state: "retired")
    private_space.update!(state: "active")
    @owner.create_equibles_connection!(api_key: "original-offline-test-key")
    private_part = evidence("Original private issuer revenue.", space: private_space, provider: "equibles", listing: "US:TEST",
                            approval: "original-offline-approval", known: nil, received: @now - 5.minutes)
    assert_equal "research_permission_required", assert_raises(Research::Error) {
      retrieve(space: private_space, listing_identity: "US:TEST")
    }.code
    settings = Research::Policy::REQUIRED.index_with { true }.merge("approval_reference" => "original-offline-approval",
      "source_kinds" => ["earnings_transcript"], "listings" => ["US:TEST"], "retention_seconds" => 3600,
      "freshness_seconds" => 600, "daily_source_requests" => 3, "expires_at" => (@now + 1.day).iso8601)
    factory = ->(owner) { Research::Policy.new(owner, configuration: { approved_owners: { owner.id.to_s => settings } }) }
    result = retrieve(space: private_space, listing_identity: "US:TEST", policy_factory: factory)
    assert JSON.parse(result.context_json)["sources"].first["uncertainty"]["knowability_unknown"]
    assert_equal 0, result.request.embedding_attempts.first.reserved_cost_nanos % ResearchEmbeddingAttempt::PRICE_PER_TOKEN
    settings["retention_seconds"] = 60
    settings["freshness_seconds"] = 30
    assert_raises(Research::Error) { result.context_json }
    settings["retention_seconds"] = 3600
    settings["freshness_seconds"] = 600
    assert_equal "historical_permission_required", assert_raises(Research::Error) {
      retrieve(space: private_space, listing_identity: "US:TEST", policy_factory: factory, mode: "as_of", as_of: @now - 1.day)
    }.code
    settings["private_display"] = false
    assert_raises(Research::Error) { result.dispatch!(publisher: ->(_) { flunk }) { flunk } }
    assert ResearchPassage.exists?(private_part.id)
  end

  test "latest discovery reservations share the source account quota and private query cost ledger" do
    @space.update!(state: "retired")
    space = new_space(@owner, provider: "openai")
    space.update!(state: "active")
    connection = @owner.create_equibles_connection!(api_key: "original-offline-latest-key")
    evidence("Original private company revenue.", space: space, provider: "equibles", listing: "US:TEST",
             approval: "original-offline-approval", known: nil, received: @now - 5.minutes,
             event_id: "00000000-0000-0000-0000-000000000003")
    settings = Research::Policy::REQUIRED.index_with { true }.merge("approval_reference" => "original-offline-approval",
      "source_kinds" => ["earnings_transcript"], "listings" => ["US:TEST"], "retention_seconds" => 3600,
      "freshness_seconds" => 600, "daily_source_requests" => 3, "expires_at" => (@now + 1.day).iso8601)
    factory = ->(owner) { Research::Policy.new(owner, configuration: { approved_owners: { owner.id.to_s => settings } }) }
    latest = Object.new
    def latest.call(before_request:, **)
      2.times { before_request.call }
      { "provider_event_id" => "00000000-0000-0000-0000-000000000003", "fiscal_year" => 2026, "fiscal_quarter" => 3,
        "event_at" => "2026-10-28T18:00:00Z", "observed_at" => Time.current.iso8601,
        "has_transcript" => true, "transcript_complete" => true }
    end
    result = retrieve(space: space, listing_identity: "US:TEST", policy_factory: factory, latest_source: latest,
                      mode: "latest_earnings", fiscal_year: nil, fiscal_period: nil)
    assert_equal "ready", result.status
    assert_equal 2, result.request.source_requests
    assert_equal 2, connection.reload.requests_used
    assert_equal @embedder.calls, 1
    attempt = result.request.embedding_attempts.first
    assert_equal attempt.actual_tokens * ResearchEmbeddingAttempt::PRICE_PER_TOKEN, attempt.actual_cost_nanos
    assert_equal "source_request_budget_exceeded", assert_raises(Research::Error) {
      retrieve(space: space, listing_identity: "US:TEST", policy_factory: factory, latest_source: latest,
               mode: "latest_earnings", fiscal_year: nil, fiscal_period: nil)
    }.code
    assert_equal 3, connection.reload.requests_used
    assert_equal 1, @embedder.calls
    connection.update!(api_key: "original-offline-rotated-key")
    assert_equal "source_credentials_changed", assert_raises(Research::Error) { result.context_json }.code
  end

  test "materialized eligible distances stay exact even when an approximate index is installed" do
    values = vector(0)
    values[1] = 0.1
    ResearchEmbedding.where(passage_id: @part.id).update_all(embedding: values)
    noise = evidence("Original unrelated issuer discussion.", listing: "SYNTH:OTHER")
    105.times do |index|
      part = noise.dup
      part.position = index + 1
      part.save!
      @space.embeddings.create!(user: @owner, passage: part, embedding: vector(0))
    end
    assert_not_includes @space.nearest(vector(0), limit: 100).map(&:passage_id), @part.id
    service = Research::Retriever.new(user: @owner, space: @space, query: "nonlexical question",
      request_key: SecureRandom.uuid, listing_identity: "SYNTH:ALPHA", fiscal_year: 2026, fiscal_period: "Q3",
      strategy: "hybrid", embedder: @embedder)
    result = service.call
    assert_equal [@part.id], JSON.parse(result.context_json)["sources"].map { |source| source["passage_id"] }
    ApplicationRecord.transaction do
      ApplicationRecord.connection.execute("CREATE INDEX original_m3_hnsw_trial ON research_embeddings USING hnsw (embedding vector_cosine_ops)")
      ApplicationRecord.connection.execute("SET LOCAL enable_seqscan = off")
      sql = nil
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |_, _, _, _, event|
        sql = event[:sql] if event[:sql].include?("distances AS MATERIALIZED")
      end
      baseline = Research::HybridRanker.new(rows: service.eligible, space: @space, query: "nonlexical question", vector: vector(0), recency: false).call
      assert_equal @part.id, baseline.first["passage_id"]
      plan = ApplicationRecord.connection.select_values("EXPLAIN #{sql}").join("\n")
      assert_includes plan, "CTE Scan on distances"
      assert_not_includes plan, "original_m3_hnsw_trial"
      ApplicationRecord.connection.execute("DROP INDEX original_m3_hnsw_trial")
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
    end
    assert_not ApplicationRecord.connection.select_value("SELECT to_regclass('original_m3_hnsw_trial')::text")
  end

  test "optional recency breaks fused-score ties only using known source dates" do
    newer = evidence("Original recent revenue.", known: @now - 1.hour, received: @now - 30.minutes)
    older_values = vector(0)
    newer_values = vector(0)
    older_values[1] = 0.1
    newer_values[1] = 0.01
    ResearchEmbedding.where(passage_id: @part.id).update_all(embedding: older_values)
    ResearchEmbedding.where(passage_id: newer.id).update_all(embedding: newer_values)
    baseline = retrieve(limit: 1)
    recent = retrieve(limit: 1, recency: true)
    assert_equal @part.id, JSON.parse(baseline.context_json)["sources"].first["passage_id"]
    assert_equal newer.id, JSON.parse(recent.context_json)["sources"].first["passage_id"]
  end

  private

  def retrieve(**overrides)
    Research::Retriever.new(**{ user: @owner, space: @space, query: "revenue", request_key: SecureRandom.uuid,
      listing_identity: "SYNTH:ALPHA", fiscal_year: 2026, fiscal_period: "Q3", strategy: "hybrid", embedder: @embedder }.merge(overrides)).call
  end

  def new_owner
    User.create!(email: "original-m3-#{SecureRandom.hex(10)}@example.test", password: "original-test-password").tap { |owner| @owners << owner }
  end

  def new_space(owner, provider: "synthetic")
    owner.research_embedding_spaces.create!(provider: provider, model: provider == "synthetic" ? "fixture-1536" : "text-embedding-3-small",
      model_version: provider == "synthetic" ? "sha256-v1" : "text-embedding-3-small",
      preprocessing_version: Research::Chunker::PREPROCESSING, chunker_version: Research::Chunker::VERSION)
  end

  def evidence(text, owner: @owner, space: @space, document: nil, listing: "SYNTH:ALPHA", period: "Q3",
               provider: "synthetic", instrument: nil, kind: "earnings_transcript",
               approval: "original-public-fixture-v1", known: @now - 5.days, received: @now - 1.day, position: 0,
               event_id: "original-alpha-2026-q3")
    document ||= owner.research_documents.create!(provider: provider, source_kind: kind, source_id: SecureRandom.uuid,
      listing_identity: listing, instrument_identity: instrument || "#{provider}:#{listing}", fiscal_year: 2026, fiscal_period: period,
      citation_url: "https://example.test/original-fixture", entitlement_reference: approval, rights_expires_at: @now + 30.days)
    data = { metadata: { "provider_event_id" => event_id },
             event_at: Time.iso8601("2026-10-28T18:00:00Z"), published_at: known, known_at: known, received_at: received }
    temporal = Research::TemporalEvidence.source(data, provider: "synthetic")
    normalized = Research::Chunker.normalize([{ "text" => text, "speaker" => "Original fictional speaker" }], metadata: data[:metadata])
    revision = document.revisions.create!(normalized.merge(temporal[:values]).merge(user: owner, temporal_metadata: temporal[:metadata],
      expires_at: @now + 7.days, verified_at: @now - 1.minute, fresh_until: @now + 1.hour,
      indexed_at: @now, index_state: "ready"))
    document.update!(current_revision: revision)
    part = Research::Chunker.new.call(revision).first
    passage = revision.passages.create!(part.merge(user: owner,
      preprocessing_version: Research::Chunker::PREPROCESSING, chunker_version: Research::Chunker::VERSION))
    space.embeddings.create!(user: owner, passage: passage, embedding: vector(position))
    passage
  end

  def vector(position)
    Array.new(1536, 0.0).tap { |values| values[position] = 1.0 }
  end

  class Embeddings
    attr_reader :calls, :transaction_open
    def initialize(position: 0, fail: false)
      @position, @fail, @calls = position, fail, 0
    end
    def prepare!; end
    def call(batch, **)
      @calls += 1
      @transaction_open = ApplicationRecord.connection.transaction_open?
      raise Research::Error.new("embedding_timeout") if @fail
      Research::Embedder::Result.new(vectors: [Array.new(1536, 0.0).tap { |values| values[@position] = 1.0 }],
                                    tokens: batch.sum(&:token_count))
    end
  end
end
