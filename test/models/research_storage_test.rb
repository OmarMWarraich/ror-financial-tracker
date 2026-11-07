require "test_helper"

class ResearchStorageTest < ActiveSupport::TestCase
  setup do
    @owner = users(:one)
    @other = users(:two)
    @now = Time.current.change(usec: 0)
    @document = document(@owner)
    @revision = revision(@document)
    @passage = passage(@revision)
    @space = space(@owner)
  end

  test "vector round trip and exact cosine order coexist with normal joins" do
    first = embedding(@space, @passage, vector(0))
    second_passage = passage(@revision, position: 1)
    second = embedding(@space, second_passage, vector(1))
    @space.activate!(at: @now)

    nearest = @space.nearest(vector(0), at: @now)
    assert_equal [first.id, second.id], nearest.map(&:id)
    assert_in_delta 0, nearest.first.neighbor_distance, 1e-6
    assert_in_delta 1, nearest.last.neighbor_distance, 1e-6
    assert_equal 1536, first.reload.embedding.length
    assert_in_delta 1, first.embedding.first, 1e-6
    assert_equal @document.id, nearest.first.passage.revision.document.id
    assert_equal @owner.id, nearest.first.user_id
    assert_equal "0.8.1", ResearchEmbedding.connection.select_value("SELECT extversion FROM pg_extension WHERE extname='vector'")
  end

  test "owner isolation is enforced by composite foreign keys even without validations" do
    other_document = document(@other)
    other_revision = revision(other_document)
    other_passage = passage(other_revision)
    other_space = space(@other)
    row = embedding(@space, @passage, vector(0))

    assert_database_rejects { @revision.class.where(id: @revision.id).update_all(document_id: other_document.id) }
    assert_database_rejects { @passage.class.where(id: @passage.id).update_all(revision_id: other_revision.id) }
    assert_database_rejects { row.class.where(id: row.id).update_all(passage_id: other_passage.id) }
    assert_database_rejects { row.class.where(id: row.id).update_all(space_id: other_space.id) }

    embedding(other_space, other_passage, vector(0))
    @space.activate!(at: @now)
    other_space.activate!(at: @now)
    assert_equal [row.id], @space.nearest(vector(0), at: @now).map(&:id)
    assert_equal @other.id, other_space.nearest(vector(0), at: @now).first.user_id
  end

  test "hashes and citation positions are checked in models and SQL" do
    assert_equal Digest::SHA256.hexdigest(@revision.content), @revision.checksum
    assert_equal Digest::SHA256.hexdigest(@passage.content), @passage.checksum
    assert_raises(ActiveRecord::ReadonlyAttributeError) { @passage.update!(content: "changed") }
    assert_database_rejects { ResearchPassage.where(id: @passage.id).update_all(content: "tampered") }
    assert_database_rejects { ResearchRevision.where(id: @revision.id).update_all(checksum: "a" * 64) }
    assert_database_rejects { ResearchPassage.where(id: @passage.id).update_all(position: -1) }
    assert_database_rejects { ResearchPassage.where(id: @passage.id).update_all(end_char: 9999) }
    assert_database_rejects { ResearchPassage.where(id: @passage.id).update_all(start_line: 0, end_line: 1) }
    assert_database_rejects { ResearchPassage.where(id: @passage.id).update_all(token_count: 801) }
    assert_database_rejects { ResearchRevision.where(id: @revision.id).update_all(expires_at: @revision.received_at) }
  end

  test "vector dimensions zero and nonfinite values cannot enter storage" do
    [[0.0] * 1536, [1.0, 0.0], [Float::NAN] * 1536, [Float::INFINITY] * 1536].each do |values|
      row = @space.embeddings.build(user: @owner, passage: @passage, embedding: values)
      assert_not row.valid?
      assert_database_rejects { row.save!(validate: false) }
    end
  end

  test "query validation raises explicitly for invalid values and limits" do
    [nil, [], vector(0).take(3), [0.0] * 1536, [Float::NAN] * 1536].each do |values|
      assert_raises(ArgumentError) { @space.nearest(values, at: @now) }
    end
    [0, 101, "5", nil].each do |limit|
      assert_raises(ArgumentError) { @space.nearest(vector(0), limit: limit, at: @now) }
    end
  end

  test "versions remain separate and cutover requires complete resumable coverage" do
    old_row = embedding(@space, @passage, vector(0))
    @space.activate!(at: @now)
    second_passage = passage(@revision, position: 1)
    replacement = space(@owner, model_version: "fixture-v2")
    embedding(replacement, @passage, vector(1))

    assert_raises(ArgumentError) { replacement.nearest(vector(0), at: @now) }
    assert_raises(ArgumentError) { replacement.activate!(at: @now) }
    assert_equal "active", @space.reload.state
    assert_equal [old_row.id], @space.nearest(vector(0), at: @now).map(&:id)

    resumed = embedding(replacement, second_passage, vector(0))
    assert_database_rejects do
      duplicate = resumed.dup
      duplicate.save!(validate: false)
    end
    replacement.activate!(at: @now)
    assert_equal "retired", @space.reload.state
    assert_equal "active", replacement.reload.state
    assert_equal resumed.id, replacement.nearest(vector(0), at: @now).first.id
    assert_equal 3, ResearchEmbedding.where(user: @owner).count
    assert_raises(ArgumentError) { @space.nearest(vector(0), at: @now) }
  end

  test "space identity and chunking provenance cannot be silently changed" do
    assert_raises(ActiveRecord::ReadonlyAttributeError) { @space.update!(model_version: "overwrite") }
    error = assert_database_rejects { ResearchEmbeddingSpace.where(id: @space.id).update_all(model_version: "overwrite") }
    assert_includes error.message, "identity is immutable"
    wrong_space = space(@owner, chunker_version: "sentences-v2")
    row = wrong_space.embeddings.build(user: @owner, passage: @passage, embedding: vector(0))
    assert_not row.valid?
    assert_database_rejects { row.save!(validate: false) }
    row.chunker_version = wrong_space.chunker_version
    assert_database_rejects { row.save!(validate: false) }
  end

  test "at most one space per owner is active even through direct SQL" do
    embedding(@space, @passage, vector(0))
    @space.activate!(at: @now)
    replacement = space(@owner, model_version: "fixture-v2")
    assert_database_rejects { replacement.update_columns(state: "active") }
    assert_equal "active", @space.reload.state
  end

  test "retention rights revocation unknown availability and future evidence are excluded" do
    row = embedding(@space, @passage, vector(0))
    @space.activate!(at: @now)
    assert_equal [row.id], @space.nearest(vector(0), at: @now).map(&:id)
    assert_empty @space.nearest(vector(0), at: @revision.received_at - 1.second)
    assert_empty @space.nearest(vector(0), at: @revision.expires_at)
    [nil, @now + 1.hour].each do |known_at|
      @revision.update!(known_at: known_at)
      assert_empty @space.nearest(vector(0), at: @now)
    end
    @revision.update!(known_at: @now - 2.days, revoked_at: @now)
    assert_empty @space.nearest(vector(0), at: @now)
    @revision.update!(revoked_at: nil)
    @document.update!(rights_expires_at: @now)
    assert_empty @space.nearest(vector(0), at: @now)
    assert_empty @space.nearest(vector(0), at: @now - 1.minute)
    @document.update!(rights_expires_at: @now + 1.day, revoked_at: @now)
    assert_empty @space.nearest(vector(0), at: @now)
  end

  test "historical availability cannot resurrect currently expired source text" do
    embedding(@space, @passage, vector(0))
    @space.activate!(at: @now)
    @revision.update!(expires_at: @now - 1.minute)
    assert_empty @space.nearest(vector(0), at: @now - 1.hour)
  end

  test "vector reads preserve transaction rollback and relational records" do
    embedding(@space, @passage, vector(0))
    @space.activate!(at: @now)
    original_name = @owner.first_name
    User.transaction(requires_new: true) do
      @owner.update!(first_name: "Synthetic transaction")
      assert_equal 1, @space.nearest(vector(0), at: @now).size
      assert_equal "Synthetic transaction", @owner.reload.first_name
      raise ActiveRecord::Rollback
    end
    assert_equal original_name, @owner.reload.first_name
    assert_equal 1, @space.embeddings.count
    assert_equal 2, ResearchEmbedding.connection.select_value("SELECT count(*) FROM pg_trigger WHERE tgname IN ('sandbox_events_immutable','sandbox_orders_immutable')").to_i
  end

  test "user deletion cannot silently bypass research retention" do
    assert_not @owner.destroy
    assert @owner.errors[:base].any?
    assert ResearchDocument.exists?(@document.id)
  end

  test "extension and research schema rollback is deliberately non-destructive" do
    require Rails.root.join("db/migrate/20261107060000_create_research_storage")
    assert_raises(ActiveRecord::IrreversibleMigration) { CreateResearchStorage.new.down }
    assert ResearchDocument.exists?(@document.id)
  end

  private

  def document(owner)
    owner.research_documents.create!(
      provider: "synthetic", source_kind: "earnings_transcript", source_id: SecureRandom.uuid,
      instrument_identity: "SYNTH-ALPHA", listing_identity: "SYNTH:ALPHA",
      fiscal_year: 2026, fiscal_period: "Q3", citation_url: "https://example.test/fictional-call",
      entitlement_reference: "original-fixture-v1", rights_expires_at: @now + 30.days
    )
  end

  def revision(document)
    row = document.revisions.create!(
      user: document.user, source_revision: "original",
      content: "Fictional revenue increased. This is original synthetic evidence.",
      event_at: @now - 3.days, published_at: @now - 2.days, known_at: @now - 2.days,
      received_at: @now - 1.day, expires_at: @now + 7.days, index_state: "ready"
    )
    document.update!(current_revision: row)
    row
  end

  def passage(revision, position: 0)
    revision.passages.create!(
      user: revision.user, preprocessing_version: "plain-v1", chunker_version: "sentences-v1",
      position: position, start_char: 0, end_char: revision.content.length,
      start_line: 1, end_line: 1, speaker: "Fictional management", token_count: 12, content: revision.content
    )
  end

  def space(owner, **overrides)
    owner.research_embedding_spaces.create!(
      { provider: "synthetic", model: "fixture1536", model_version: "fixture-v1",
        preprocessing_version: "plain-v1", chunker_version: "sentences-v1" }.merge(overrides)
    )
  end

  def embedding(space, passage, values)
    space.embeddings.create!(user: space.user, passage: passage, embedding: values)
  end

  def vector(position)
    Array.new(1536, 0.0).tap { |values| values[position] = 1.0 }
  end

  def assert_database_rejects(&block)
    assert_raises(ActiveRecord::StatementInvalid) do
      ActiveRecord::Base.transaction(requires_new: true, &block)
    end
  end
end
