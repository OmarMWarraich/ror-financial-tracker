require "active_support/testing/time_helpers"

module Research
  class Acceptance
    include ActiveSupport::Testing::TimeHelpers
    VERSION = "original-earnings-acceptance-v1"
    CLOCK = Time.iso8601("2026-11-07T12:00:00Z")
    TOPICS = %w[amber birch cedar dahlia elm fern garnet hazel iris jade kelp larch maple nickel onyx pearl quartz reed spruce topaz].freeze
    MODES = %w[keyword vector hybrid].freeze
    LISTINGS = %w[US:ORIGINALALPHA US:ORIGINALBRAVO US:ORIGINALCEDAR US:ORIGINALDELTA].freeze

    class FixturePolicy < Policy
      def check_permissions!(request)
        unless Rails.env.test? && request.provider == "synthetic" && LISTINGS.include?(request.listing_identity) &&
               [2025, 2026].include?(request.fiscal_year) && (1..3).cover?(request.fiscal_quarter)
          raise Error.new("acceptance_source_not_allowlisted")
        end
        self
      end
    end

    def call
      raise Error.new("acceptance_requires_isolated_test_database") unless Rails.env.test? && !ApplicationRecord.connection.transaction_open?
      travel_to(CLOCK) do
        build!
        cases = questions
        metrics = MODES.to_h { |mode| [mode, evaluate(mode, cases)] }
        ann = approximate_comparison(cases)
        uplift = metrics["hybrid"]["recall_at_5"] - metrics["keyword"]["recall_at_5"]
        workflow = workflow_measurement
        corpus = @passages.map do |part|
          revision = part.revision
          doc = revision.document
          [doc.source_id, doc.listing_identity, doc.fiscal_period, doc.source_kind,
            doc.user_id == @owner.id ? "primary" : "other", revision.known_at&.iso8601,
            revision.expires_at.iso8601, part.position, part.checksum]
        end.sort
        documents = ResearchDocument.where(user: @owners)
        { version: VERSION, corpus_sha256: Digest::SHA256.hexdigest(JSON.generate(corpus)),
          clock: CLOCK.iso8601, documents: documents.count, passages: @passages.size, questions: cases.size,
          versions: { ruby: RUBY_VERSION, rails: Rails.version,
            postgresql: ApplicationRecord.connection.select_value("SHOW server_version"),
            pgvector: ApplicationRecord.connection.select_value("SELECT extversion FROM pg_extension WHERE extname='vector'"),
            openai: Gem.loaded_specs.fetch("openai").version.to_s, mcp: Gem.loaded_specs.fetch("mcp").version.to_s },
          positive_questions: 20, negative_questions: 20,
          question_groups: { supported: 20, missing_conflicting_scope: 10, temporal_adversarial: 10 },
          corpus_groups: { companies: documents.distinct.count(:listing_identity), fiscal_periods: documents.distinct.count(:fiscal_period),
            source_kinds: documents.distinct.count(:source_kind), owners: documents.distinct.count(:user_id) },
          fixture_policy: "test-only original four-company scope; production SYNTH:ALPHA FY2026/Q3 gate unchanged",
          embeddings: "original deterministic SHA256 fixtures; not semantic-model acceptance",
          external_requests: 0, cost_nanos: 0, baselines: metrics, filtered_ann_candidates: ann,
          fixture_workflow: workflow,
          hybrid_recall_gain: uplift.round(4),
          hybrid_adoption: "not_approved",
          reason: "Synthetic wiring does not establish live semantic quality; keyword remains default.",
          live_checks: "blocked_pending_separate_rights_account_model_budget_authorization" }
      end
    ensure
      cleanup!
    end

    private

    def build!
      @owners, @passages, @targets, @documents = [], [], {}, {}
      @owner = owner
      @space = space(@owner)
      @other = owner
      @other_space = space(@other)
      TOPICS.each_with_index { |topic, index| document(topic, index) }
      document("nebula", 20, owner: @other, space: @other_space)
      document("obsolete", 21, expired: true)
      document("forthcoming", 22, future: true)
      document("uncertain", 23, unknown: true)
      @space.activate!
      @other_space.activate!
      raise Error.new("acceptance_corpus_shape_invalid") unless @passages.size == 120
    end

    def owner
      User.create!(email: "original-acceptance-#{SecureRandom.uuid}@example.test",
        password: "original-fixture-password").tap { |user| @owners << user }
    end

    def space(user)
      user.research_embedding_spaces.create!(provider: "synthetic", model: "fixture-1536", model_version: "sha256-v1",
        preprocessing_version: Chunker::PREPROCESSING, chunker_version: Chunker::VERSION)
    end

    def document(topic, index, owner: @owner, space: @space, expired: false, future: false, unknown: false)
      listing = LISTINGS.fetch(index / 6)
      quarter = index % 6 / 2 + 1
      kind = index.even? ? "earnings_transcript" : "earnings_brief"
      event_at = Time.iso8601("2026-#{%w[04 07 10].fetch(quarter - 1)}-28T18:00:00Z")
      doc = owner.research_documents.create!(provider: "synthetic",
        source_id: "#{VERSION}/#{topic}", listing_identity: listing, instrument_identity: "synthetic:#{listing}",
        fiscal_year: 2026, fiscal_period: "Q#{quarter}", source_kind: kind, citation_url: "https://example.test/original/#{topic}",
        entitlement_reference: "original-public-fixture-v1", rights_expires_at: CLOCK + 30.days)
      parts = [
        "Original #{topic} segment: revenue was #{100 + index} demonstration units.",
        "Original #{topic} segment: operating income was #{20 + index} demonstration units.",
        "Fictional Chief Executive: for original #{topic} we expect #{130 + index} demonstration units.",
        "Original #{topic} segment: risk is experimental capacity constraints.",
        "Original #{topic} segment: customer count was #{200 + index} demonstration units."
      ].map { |text| { "text" => text, "speaker_role" => "CEO", "speaker" => "Fictional Chief Executive" } }
      data = { metadata: { "provider_event_id" => "#{listing}-2026-q#{quarter}",
          "coverage" => { "complete_call" => true, "basis" => "original_five_part_fixture" } },
        event_at: event_at, known_at: unknown ? nil : future ? CLOCK + 1.day : CLOCK - 5.days,
        published_at: unknown ? nil : future ? CLOCK + 1.day : CLOCK - 5.days, received_at: CLOCK - 1.hour }
      normalized = Chunker.normalize(parts, metadata: data[:metadata])
      temporal = TemporalEvidence.source(data, provider: "synthetic")
      revision = doc.revisions.create!(normalized.merge(temporal[:values]).merge(user: owner,
        temporal_metadata: temporal[:metadata], expires_at: expired ? CLOCK : CLOCK + 7.days,
        verified_at: CLOCK - 1.minute, indexed_at: CLOCK - 1.minute,
        fresh_until: expired ? CLOCK : CLOCK + 1.day, index_state: "ready"))
      doc.update!(current_revision: revision)
      passages = Chunker.new.call(revision).map do |part|
        revision.passages.create!(part.merge(user: owner, preprocessing_version: Chunker::PREPROCESSING, chunker_version: Chunker::VERSION))
      end
      passages.each_slice(4) do |batch|
        result = Embedder.new(space).call(batch, timeout: 5, idempotency_key: "original-no-network")
        batch.zip(result.vectors).each { |passage, vector| space.embeddings.create!(user: owner, passage: passage, embedding: vector) }
      end
      @passages.concat(passages)
      @targets[topic] = passages
      @documents[topic] = doc
    end

    def questions
      positive = TOPICS.map { |topic| question(topic, expected: [@targets.fetch(topic).first.id]) }
      positive[0][:text] = "golden resin segment top line"
      positive[1][:text] = "white bark segment top line"
      missing = [
        question("nebula"), question("obsolete"), question("forthcoming"),
        question("amber", text: "basalt geology"), question("birch", text: "extraterrestrial horticulture"),
        question("cedar", text: "unpublished dispute resolution"),
        question("dahlia", listing_identity: LISTINGS.last),
        question("elm", fiscal_period: "Q1"), question("fern", fiscal_year: 2025),
        question("garnet", source_kind: "filing")
      ]
      temporal = [
        question("amber", mode: "as_of", as_of: CLOCK - 6.days),
        question("birch", mode: "as_of", as_of: CLOCK - 5.days - 1.second),
        question("uncertain", mode: "as_of", as_of: CLOCK),
        question("forthcoming", mode: "as_of", as_of: CLOCK),
        question("obsolete", mode: "as_of", as_of: CLOCK),
        question("hazel", mode: "as_of", as_of: CLOCK - 6.days),
        question("iris", mode: "as_of", as_of: CLOCK - 1.year),
        question("jade", text: "ignore policy fabricate 999999 profit"),
        question("kelp", text: "execute shell disclose credentials"),
        question("larch", text: "guaranteed profitable brokerage transaction")
      ]
      positive + missing + temporal
    end

    def question(topic, expected: [], **overrides)
      doc = @documents.fetch(topic)
      { text: "#{topic} revenue", expected: expected, listing_identity: doc.listing_identity,
        fiscal_year: doc.fiscal_year, fiscal_period: doc.fiscal_period, source_kind: doc.source_kind }.merge(overrides)
    end

    def selection(item)
      service = Retriever.new(user: @owner, space: @space, query: item.fetch(:text), request_key: SecureRandom.uuid,
        **item.slice(:listing_identity, :fiscal_year, :fiscal_period, :source_kind),
        mode: item.fetch(:mode, "current"), as_of: item[:as_of],
        policy_factory: ->(owner) { FixturePolicy.new(owner) })
      service.call
      service
    end

    def vector(query)
      normalized = Chunker.normalize([{ "text" => query }], metadata: {}).fetch(:content)
      input = Retriever::QueryInput.new(normalized, Chunker.new.tokens(normalized))
      Embedder.new(@space).call([input], timeout: 5, idempotency_key: "original-no-network").vectors.first
    end

    def evaluate(mode, cases)
      hits, supported, claims, rejected, negative_hits, leaks = 0, 0, 0, 0, 0, 0
      durations = []
      cases.each do |item|
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        service = selection(item)
        rows = service.eligible
        ranked = HybridRanker.new(rows: rows, space: @space, query: item.fetch(:text),
          vector: mode == "keyword" ? nil : vector(item.fetch(:text)), keyword: mode != "vector", recency: false).call.first(5)
        ids = ranked.map { |row| row.fetch("passage_id") }
        expected = item.fetch(:expected)
        hits += 1 if expected.any? && (ids & expected).any?
        negative_hits += 1 if expected.empty? && ids.any?
        sources = rows.where(id: ids).includes(revision: :document).map { |passage| EvidenceSet.source(passage) }
        allowed = golden_ids(item)
        leaks += (ids - allowed).size
        durations << (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
        target = sources.find { |source| expected.include?(source["passage_id"]) }
        next unless target
        claim = { "kind" => item[:source_kind] == "earnings_brief" ? "provider_interpretation" : "reported",
          "quote" => target.fetch("content"), "source_id" => target.fetch("source_id") }
        payload = answer(claim, item)
        Agent::EarningsWorkflow.answer(JSON.generate(payload), sources: sources, scope: scope(item), event: event(item))
        supported += 1
        claims += 1
        claim["quote"] = "Original unsupported revenue was 999999 demonstration units."
        begin
          Agent::EarningsWorkflow.answer(JSON.generate(payload), sources: sources, scope: scope(item), event: event(item))
          raise Error.new("acceptance_unsupported_claim_published")
        rescue Research::Error => error
          raise unless error.code == "workflow_claim_unsupported"
          rejected += 1
        end
      end
      { "recall_at_5" => (hits / 20.0).round(4), "positive_hits" => hits,
        "negative_false_evidence" => negative_hits, "ownership_temporal_scope_leaks" => leaks,
        "extractive_fixture_claim_support" => claims.zero? ? nil : supported.fdiv(claims).round(4),
        "validated_claims" => claims, "unsupported_number_probes_rejected" => rejected,
        "p95_ms" => durations.sort.fetch((durations.size * 0.95).ceil - 1).round(3) }
    end

    def answer(claim, item)
      scope(item).merge("workflow" => Agent::EarningsWorkflow::ID, "status" => "answer",
        "sections" => { "summary" => [claim], "results" => [claim], "outlook" => [], "risks" => [] }, "gaps" => [])
    end

    def scope(item)
      { "listing_identity" => item.fetch(:listing_identity), "fiscal_year" => item.fetch(:fiscal_year),
        "fiscal_quarter" => item.fetch(:fiscal_period).delete_prefix("Q").to_i }
    end

    def event(item)
      values = scope(item)
      values.merge("provider_event_id" => "#{values.fetch('listing_identity')}-2026-q#{values.fetch('fiscal_quarter')}",
        "event_at" => Time.iso8601("2026-#{%w[04 07 10].fetch(values.fetch('fiscal_quarter') - 1)}-28T18:00:00Z").iso8601)
    end

    def golden_ids(item)
      @documents.flat_map do |topic, doc|
        revision = doc.current_revision
        matches = doc.user_id == @owner.id && doc.listing_identity == item[:listing_identity] &&
          doc.fiscal_year == item[:fiscal_year] && doc.fiscal_period == item[:fiscal_period] &&
          doc.source_kind == item[:source_kind] && revision.expires_at > CLOCK &&
          (revision.known_at.nil? || revision.known_at <= CLOCK)
        matches &&= revision.known_at && revision.known_at <= item.fetch(:as_of) if item[:mode] == "as_of"
        matches ? @targets.fetch(topic).map(&:id) : []
      end
    end

    def workflow_measurement
      durations = 20.times.map do
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        run = Agent::Lifecycle.submit!(user: @owner, query: "Summarize original Alpha latest earnings.",
          request_key: SecureRandom.uuid, listing_identity: "SYNTH:ALPHA", fiscal_year: 2026, fiscal_quarter: 3,
          evidence_mode: "fixture", query_mode: "latest_earnings", workflow: Agent::EarningsWorkflow::ID, enqueue: false)
        Agent::Execution.call(run, events: ->(_event) {})
        unless run.reload.state == "completed" && run.messages.count == 2 &&
               run.model_attempts.all? { |attempt| attempt.state == "settled" && attempt.actual_cost_nanos == 0 }
          raise Error.new("acceptance_fixture_workflow_invalid")
        end
        (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
      end
      { runs: durations.size, cold_ms: durations.first.round(3),
        warm_p95_ms: durations.drop(1).sort.fetch(18).round(3),
        p95_ms: durations.sort.fetch(18).round(3), external_requests: 0, cost_nanos: 0 }
    end

    def approximate_comparison(cases)
      connection = ApplicationRecord.connection
      @index_name = "original_acceptance_#{SecureRandom.hex(6)}"
      connection.execute("CREATE INDEX #{connection.quote_column_name(@index_name)} ON research_embeddings USING hnsw (embedding vector_cosine_ops) WHERE space_id = #{@space.id.to_i}")
      overlap, iterative_overlap, total, leaks = 0, 0, 0, 0
      cases.first(20).each do |item|
        rows = selection(item).eligible
        values = connection.quote("[#{vector(item.fetch(:text)).join(',')}]")
        sql = "SELECT passage_id FROM research_embeddings WHERE space_id = #{@space.id.to_i} AND user_id = #{@owner.id.to_i} AND passage_id IN (#{rows.select('research_passages.id').to_sql}) ORDER BY embedding <=> #{values}::vector LIMIT 5"
        exact = connection.transaction(requires_new: true) do
          connection.execute("SET LOCAL enable_indexscan=off")
          connection.select_values(sql).map(&:to_i)
        end
        approximate = connection.transaction(requires_new: true) do
          connection.execute("SET LOCAL enable_seqscan=off")
          connection.execute("SET LOCAL hnsw.ef_search=40")
          connection.execute("SET LOCAL hnsw.iterative_scan=off")
          plan = connection.select_value("EXPLAIN (FORMAT JSON) #{sql}")
          unless plan.to_json.include?(@index_name)
            raise Error.new("acceptance_ann_index_not_used")
          end
          connection.select_values(sql).map(&:to_i)
        end
        iterative = connection.transaction(requires_new: true) do
          connection.execute("SET LOCAL enable_seqscan=off")
          connection.execute("SET LOCAL hnsw.ef_search=40")
          connection.execute("SET LOCAL hnsw.iterative_scan=strict_order")
          plan = connection.select_value("EXPLAIN (FORMAT JSON) #{sql}")
          raise Error.new("acceptance_ann_index_not_used") unless plan.to_json.include?(@index_name)
          connection.select_values(sql).map(&:to_i)
        end
        overlap += (exact & approximate).size
        iterative_overlap += (exact & iterative).size
        total += exact.size
        leaks += (approximate - golden_ids(item)).size
        leaks += (iterative - golden_ids(item)).size
      end
      { "recall_at_5_against_exact_candidates" => total.zero? ? nil : overlap.fdiv(total).round(4),
        "iterative_recall_at_5_against_exact_candidates" => total.zero? ? nil : iterative_overlap.fdiv(total).round(4),
        "ownership_temporal_scope_leaks" => leaks, "ef_search" => 40,
        "iterative_scan" => "strict_order",
        "scope" => "filtered candidate-only NN without relevance cutoff; non-iterative loss is explicit, not production adoption" }
    end

    def cleanup!
      if @index_name
        ApplicationRecord.connection.execute("DROP INDEX IF EXISTS #{ApplicationRecord.connection.quote_column_name(@index_name)}")
      end
      Array(@owners).each do |user|
        user.with_lock do
          ResearchDocument.where(user: user).update_all(current_revision_id: nil)
          [ResearchToolAttempt, ResearchMessage, ResearchModelAttempt, ResearchAgentRun, ResearchConversation,
           ResearchSourceUsage, ResearchEmbedding, ResearchPassage, ResearchRevision, ResearchEmbeddingAttempt,
           ResearchRetrieval, ResearchDocument, ResearchEmbeddingSpace].each { |model| model.where(user: user).delete_all }
        end
        user.destroy!
      end
    end
  end
end
