module Research
  class Disposal
    BATCH_SIZE = 100
    PERMISSION_ERRORS = %w[research_permission_required source_not_allowlisted].freeze
    DERIVED_ERRORS = %w[chat_retention_expired agent_permission_required mcp_permission_required
      historical_permission_required chat_retention_approval_required agent_credentials_or_policy_changed
      openai_credentials_required equibles_credentials_required source_credentials_changed
      research_permission_required evidence_changed_or_disallowed no_evidence_for_dispatch evidence_dependency_missing].freeze
    Selector = Struct.new(:provider, :source_kind, :listing_identity, :fiscal_year, :fiscal_quarter, :fixture_version,
      keyword_init: true)

    def self.sweep!(user: nil, policy_factory: ->(owner) { Policy.new(owner) })
      counts = { documents: 0, revisions: 0, passages: 0, embeddings: 0, messages: 0,
        maximum_known_expiry_lag_seconds: nil, unknown_disposal_deadlines: 0 }
      documents = user ? user.research_documents : ResearchDocument.all
      documents.find_each(batch_size: BATCH_SIZE) do |document|
        document.user.with_lock do
          document.reload
          approval = policy_factory.call(document.user)
          selector = Selector.new(provider: document.provider, source_kind: document.source_kind,
            listing_identity: document.listing_identity, fiscal_year: document.fiscal_year,
            fiscal_quarter: document.fiscal_period.delete_prefix("Q").to_i, fixture_version: "v1")
          revoked = document.revoked_at || document.rights_expires_at <= Time.current ||
            (document.provider == "equibles" && !document.user.equibles_connection)
          unless revoked
            begin
              approval.check_permissions!(selector)
              revoked = document.entitlement_reference != approval.reference(selector)
            rescue Research::Error => error
              raise unless PERMISSION_ERRORS.include?(error.code)
              revoked = true
            end
          end
          revisions = ResearchRevision.where(user_id: document.user_id, document_id: document.id)
          if revoked
            ids = revisions.pluck(:id)
          else
            expired = revisions.where("expires_at <= ? OR received_at <= ? OR revoked_at IS NOT NULL",
              Time.current, Time.current - approval.retention(selector))
            expired = expired.or(revisions.where.not(superseded_at: nil)) unless approval.history?(selector)
            ids = expired.pluck(:id)
          end
          if ids.any? || (revoked && !document.revoked_at)
            deadlines = revisions.where(id: ids).pluck(:expires_at, :revoked_at).flatten.compact +
              [document.revoked_at, document.rights_expires_at].compact
            deadlines += revisions.where(id: ids).pluck(:received_at).map { |time| time + approval.retention(selector) } unless revoked
            known = deadlines.select { |deadline| deadline <= Time.current }
            if known.any?
              lag = Time.current - known.min
              counts[:maximum_known_expiry_lag_seconds] = [counts[:maximum_known_expiry_lag_seconds], lag].compact.max.round(3)
            else
              counts[:unknown_disposal_deadlines] += 1
            end
            result = purge_document!(document, revision_ids: ids, revoke: !!revoked)
            result.each { |key, count| counts[key] += count }
          end
        end
      end
      messages = user ? user.research_messages : ResearchMessage.all
      ResearchAgentRun.where(id: messages.where.not(state: "redacted").select(:run_id)).find_each(batch_size: BATCH_SIZE) do |run|
        run.user.with_lock do
          if RestoreGate.pending?
            counts[:messages] += invalidate_run!(run, code: "restore_chat_redacted")
            next
          end
          begin
            run.messages.where.not(state: "redacted").each(&:readable_content!)
          rescue Research::Error => error
            raise unless DERIVED_ERRORS.include?(error.code)
            counts[:messages] += invalidate_run!(run, code: "derived_evidence_disallowed")
          end
        end
      end
      Rails.logger.info("Research disposal #{counts.map { |key, count| "#{key}=#{count}" }.join(' ')}")
      counts
    end

    def self.purge_document!(document, revision_ids: nil, revoke: true)
      document.user.with_lock do
        document.reload
        tombstoned = revoke && document.revoked_at.nil?
        revisions = ResearchRevision.where(user_id: document.user_id, document_id: document.id)
        revisions = revisions.where(id: revision_ids) if revision_ids
        ids = revisions.pluck(:id)
        passages = ResearchPassage.where(user_id: document.user_id, revision_id: ids)
        passage_ids = passages.pluck(:id)
        runs = []
        document.user.research_retrievals.where.not(selection: []).find_each(batch_size: BATCH_SIZE) do |request|
          next unless request.selection.any? { |item| passage_ids.include?(item["passage_id"]) }
          runs << request.agent_run if request.agent_run
          request.embedding_attempts.where(state: "reserved").update_all(state: "released", error_code: "evidence_disposed")
          request.embedding_attempts.where(state: "dispatched").update_all(state: "uncertain", error_code: "evidence_disposed")
          request.update!(selection: [], state: "failed", error_code: "evidence_disposed", generation: request.generation + 1)
        end
        document.user.research_messages.where(role: "assistant").where.not(state: "redacted").find_each(batch_size: BATCH_SIZE) do |message|
          runs << message.run if message.sources.any? { |source| ids.include?(source["revision_id"]) ||
            passage_ids.include?(source["passage_id"]) || (revoke && source["document_id"] == document.id) }
        end
        messages = runs.uniq(&:id).sum { |run| invalidate_run!(run, code: "evidence_disposed") }
        if tombstoned || ids.include?(document.current_revision_id)
          document.update!(current_revision_id: nil, ingestion_generation: document.ingestion_generation + 1,
            revoked_at: revoke ? (document.revoked_at || Time.current) : document.revoked_at)
        end
        requests = ResearchIngestion.where(user_id: document.user_id, document_id: document.id)
        requests = requests.where(source_revision: revisions.select(:source_revision)) unless revoke
        ResearchEmbeddingAttempt.where(ingestion_id: requests.select(:id), state: "reserved")
          .update_all(state: "released", error_code: "evidence_disposed")
        ResearchEmbeddingAttempt.where(ingestion_id: requests.select(:id), state: "dispatched")
          .update_all(state: "uncertain", error_code: "evidence_disposed")
        requests.update_all(state: "failed", error_code: "evidence_disposed", lease_token: nil, lease_expires_at: nil)
        embeddings = ResearchEmbedding.where(user_id: document.user_id, passage_id: passage_ids).delete_all
        deleted_passages = passages.delete_all
        deleted_revisions = revisions.delete_all
        { documents: tombstoned ? 1 : 0, revisions: deleted_revisions, passages: deleted_passages,
          embeddings: embeddings, messages: messages }
      end
    end

    def self.invalidate_run!(run, code:)
      Agent::Lifecycle.terminal!(run, state: "cancelled", code: code)
      run.messages.where.not(state: "redacted").update_all(content: nil, source_ids: [], sources: [], state: "redacted")
    end

    def self.purge_owner!(user, private_only: false)
      user.with_lock do
        documents = user.research_documents
        documents = documents.where(provider: "equibles") if private_only
        documents.find_each(batch_size: BATCH_SIZE) { |document| purge_document!(document) }
        runs = user.research_agent_runs
        runs = runs.where.not(provider: "fixture") if private_only
        runs.find_each(batch_size: BATCH_SIZE) { |run| invalidate_run!(run, code: "owner_research_deleted") }
      end
    end
  end
end
