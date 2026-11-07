require "test_helper"

class ResearchDisposalTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @owner = User.create!(email: "original-disposal-#{SecureRandom.uuid}@example.test", password: "original-fixture-password")
    @space = @owner.research_embedding_spaces.create!(provider: "synthetic", model: "fixture-1536", model_version: "sha256-v1",
      preprocessing_version: Research::Chunker::PREPROCESSING, chunker_version: Research::Chunker::VERSION)
    @ingestion = ingest
    @document = @ingestion.document
    @revision = @document.current_revision
    @space.activate!
    @previous = ENV["RESEARCH_RESTORE_PENDING"]
  end

  teardown do
    @previous ? ENV["RESEARCH_RESTORE_PENDING"] = @previous : ENV.delete("RESEARCH_RESTORE_PENDING")
    @owner.with_lock do
      ResearchDocument.where(user: @owner).update_all(current_revision_id: nil)
      [ResearchEmbedding, ResearchPassage, ResearchRevision, ResearchEmbeddingAttempt, ResearchRetrieval,
       ResearchIngestion, ResearchDocument, ResearchEmbeddingSpace, ResearchToolAttempt, ResearchMessage,
       ResearchModelAttempt, ResearchAgentRun, ResearchConversation, ResearchSourceUsage].each { |model| model.where(user: @owner).delete_all }
    end
    @owner.destroy!
  end

  test "delayed cleanup cannot display source-derived user questions or answers and purge clears the dependency graph" do
    evidence = retrieve
    run = derived_run(evidence)
    @revision.update!(expires_at: Time.current, fresh_until: nil)
    run.messages.each { |message| assert_raises(Research::Error) { message.readable_content! } }
    counts = Research::Disposal.sweep!(user: @owner)
    assert_equal 1, counts[:revisions]
    assert_equal 2, counts[:passages]
    assert_equal 2, counts[:embeddings]
    assert_equal 2, counts[:messages]
    assert_operator counts[:maximum_known_expiry_lag_seconds], :>=, 0
    assert_equal "evidence_disposed", evidence.request.reload.error_code
    assert_equal [], evidence.request.selection
    assert run.messages.reload.all? { |message| message.state == "redacted" && message.content.nil? && message.sources.empty? }
    assert_nil @document.reload.current_revision_id
    assert_empty @space.embeddings
    assert_raises(Research::Error) { evidence.context_json }
    assert ResearchDocument.exists?(@document.id)
    assert_equal 0, Research::Disposal.sweep!(user: @owner)[:revisions]
  end

  test "permitted superseded history and stale-but-useful evidence survive until deletion deadline" do
    newer = ingest(version: "v2")
    @revision.update!(fresh_until: 1.hour.ago)
    assert @revision.reload.superseded_at
    assert_equal 0, Research::Disposal.sweep!(user: @owner)[:revisions]
    assert ResearchRevision.exists?(@revision.id)
    assert ResearchRevision.exists?(newer.document.current_revision_id)
    factory = ->(owner) do
      Research::Policy.new(owner).tap { |policy| policy.define_singleton_method(:history?) { |_| false } }
    end
    assert_equal 1, Research::Disposal.sweep!(user: @owner, policy_factory: factory)[:revisions]
    assert_equal newer.document.current_revision_id, @document.reload.current_revision_id
  end

  test "owner deletion cancels queued work and cannot refund uncertain billing or recreate a purged revision" do
    evidence = retrieve
    run = derived_run(evidence, completed: false)
    receipt = ResearchEmbeddingAttempt.reserve!(@ingestion, tokens: 100, batch_key: SecureRandom.uuid, paid: true)
    receipt.update!(state: "dispatched")
    cost = Research::Agent::Spend.cost(user_id: @owner.id)
    Research::Disposal.purge_owner!(@owner)
    assert_equal "cancelled", run.reload.state
    assert_equal "uncertain", receipt.reload.state
    assert_equal cost, Research::Agent::Spend.cost(user_id: @owner.id)
    generation = @document.reload.ingestion_generation
    Research::Disposal.purge_owner!(@owner)
    assert_equal generation, @document.reload.ingestion_generation
    assert_equal cost, Research::Agent::Spend.cost(user_id: @owner.id)
    replay = ingest
    assert_equal "source_revoked_or_expired", replay.error_code
    assert_empty @document.revisions
    assert_empty @space.embeddings
  end

  test "cleanup during an accepted embedding cannot publish or resurrect deleted material" do
    @document.purge_superseded!
    request = @owner.research_ingestions.create!(space: @space, request_key: SecureRandom.uuid, provider: "synthetic",
      source_kind: "earnings_brief", listing_identity: "SYNTH:ALPHA", fiscal_year: 2026, fiscal_quarter: 3, fixture_version: "v1")
    embedder = Object.new
    embedder.define_singleton_method(:prepare!) { }
    embedder.define_singleton_method(:call) do |batch, **|
      Research::Disposal.purge_document!(request.reload.document)
      Research::Embedder::Result.new(vectors: batch.map { Array.new(1536, 0.0).tap { |v| v[0] = 1.0 } },
        tokens: batch.sum(&:token_count))
    end
    assert_equal "stale_ingestion", assert_raises(Research::Error) { Research::Ingestor.new(request, embedder: embedder).call }.code
    assert_equal "failed", request.reload.state
    assert_empty request.document.revisions
    assert_empty ResearchEmbedding.joins(passage: :revision).where(research_revisions: { document_id: request.document_id })
    assert_equal "settled", request.embedding_attempts.first.state
  end

  test "policy uncertainty does not silently erase corpus and retired embedding space is not loss of rights" do
    @space.update!(state: "retired")
    assert_equal 0, Research::Disposal.sweep!(user: @owner)[:revisions]
    factory = ->(_) { raise Research::Error.new("research_policy_invalid") }
    assert_equal "research_policy_invalid", assert_raises(Research::Error) {
      Research::Disposal.sweep!(user: @owner, policy_factory: factory)
    }.code
    assert ResearchRevision.exists?(@revision.id)
  end

  test "restore gate blocks dispatch while review interrupts copied work without automatic replay" do
    run = Research::Agent::Lifecycle.submit!(user: @owner, query: "Original copied request.", request_key: SecureRandom.uuid,
      listing_identity: "SYNTH:ALPHA", fiscal_year: 2026, fiscal_quarter: 3, enqueue: false)
    @revision.update!(expires_at: Time.current, fresh_until: nil)
    ENV["RESEARCH_RESTORE_PENDING"] = "1"
    assert_equal "research_restore_review_required", assert_raises(Research::Error) { retrieve }.code
    assert_equal "research_restore_review_required", assert_raises(Research::Error) { Research::Agent::Policy.new(@owner).check!(run) }.code
    assert_equal 1, Research::RestoreGate.review!(user: @owner)[:revisions]
    assert_equal "interrupted", run.reload.state
    assert_equal "restore_interrupted_no_replay", run.error_code
    assert Research::RestoreGate.pending?
  end

  test "copied in-flight query and ingestion reservations remain uncertain instead of paying again" do
    request = @owner.research_retrievals.create!(space: @space, request_key: SecureRandom.uuid,
      query_digest: Digest::SHA256.hexdigest("Original copied query."), selectors: {}, deadline_at: 1.minute.from_now)
    receipt = ResearchEmbeddingAttempt.reserve!(request, tokens: 100, batch_key: SecureRandom.uuid, paid: true)
    receipt.update!(state: "dispatched")
    pending = @owner.research_ingestions.create!(space: @space, request_key: SecureRandom.uuid, provider: "synthetic",
      source_kind: "earnings_brief", listing_identity: "SYNTH:ALPHA", fiscal_year: 2026, fiscal_quarter: 3, fixture_version: "v1")
    ENV["RESEARCH_RESTORE_PENDING"] = "1"
    cost = Research::Agent::Spend.cost(user_id: @owner.id)
    Research::RestoreGate.review!(user: @owner)
    assert_equal "failed", request.reload.state
    assert_equal "uncertain", receipt.reload.state
    assert_equal "failed", pending.reload.state
    assert_equal cost, Research::Agent::Spend.cost(user_id: @owner.id)
  end

  test "connection removal deletes private fixture-derived corpus but not other sources or shared usage" do
    connection = @owner.create_equibles_connection!(api_key: "original-offline-#{SecureRandom.uuid}")
    connection.update!(quota_date: Time.current.utc.to_date, requests_used: 1)
    document = @owner.research_documents.create!(provider: "equibles", source_kind: "earnings_transcript",
      source_id: "original-private-deletion", instrument_identity: "equibles:US:TEST", listing_identity: "US:TEST",
      fiscal_year: 2026, fiscal_period: "Q3", citation_url: "https://example.test/original",
      entitlement_reference: "original-offline-permission", rights_expires_at: 1.day.from_now)
    attributes = @revision.attributes.except("id", "created_at", "updated_at", "document_id", "user_id")
    revision = document.revisions.create!(attributes.merge(user: @owner))
    document.update!(current_revision: revision)
    passage = revision.passages.create!(@revision.passages.first.attributes.except("id", "created_at", "updated_at", "revision_id", "user_id", "search_vector").merge(user: @owner))
    @space.embeddings.create!(user: @owner, passage: passage, embedding: Array.new(1536, 0.0).tap { |v| v[0] = 1.0 })
    connection.destroy!
    assert_empty document.revisions.reload
    assert document.reload.revoked_at
    assert_nil document.current_revision_id
    assert_equal 1, @owner.research_documents.where(provider: "synthetic").count
    assert_equal 2, @space.embeddings.count
    assert_equal 1, ResearchSourceUsage.where(user: @owner).sum(:requests_used)
  end

  test "missing local source dependencies fail closed for both halves of a derived conversation" do
    run = derived_run(retrieve, attach: false)
    run.messages.each do |message|
      assert_equal "evidence_dependency_missing", assert_raises(Research::Error) { message.readable_content! }.code
    end
    assert_equal 2, Research::Disposal.sweep!(user: @owner)[:messages]
  end

  private

  def ingest(version: "v1")
    request = @owner.research_ingestions.create!(space: @space, request_key: SecureRandom.uuid, provider: "synthetic",
      source_kind: "earnings_transcript", listing_identity: "SYNTH:ALPHA", fiscal_year: 2026, fiscal_quarter: 3, fixture_version: version)
    Research::Ingestor.new(request).call
    request.reload
  end

  def retrieve
    Research::Retriever.new(user: @owner, space: @space, query: "revenue", request_key: SecureRandom.uuid,
      listing_identity: "SYNTH:ALPHA", fiscal_year: 2026, fiscal_period: "Q3").call
  end

  def derived_run(evidence, completed: true, attach: true)
    run = Research::Agent::Lifecycle.submit!(user: @owner, query: @revision.content, request_key: SecureRandom.uuid,
      listing_identity: "SYNTH:ALPHA", fiscal_year: 2026, fiscal_quarter: 3, enqueue: false)
    evidence.request.update!(agent_run: run) if attach
    if completed
      Research::Agent::Lifecycle.claim!(run)
      run.update!(state: "completed", finished_at: Time.current, lease_token: nil, lease_until: nil)
      run.messages.create!(user: @owner, conversation: run.conversation, role: "assistant", state: "complete",
        content: "Original evidence-derived answer.", source_ids: [@document.source_id],
        sources: [JSON.parse(evidence.context_json)["sources"].first.except("content")], expires_at: 1.hour.from_now)
    end
    run
  end
end
