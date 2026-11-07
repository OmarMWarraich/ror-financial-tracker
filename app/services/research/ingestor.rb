module Research
  class Ingestor
    def self.enqueue!(user:, space:, **attributes)
      allowed = %i[request_key provider source_kind listing_identity fiscal_year fiscal_quarter fixture_version]
      raise Error.new("invalid_ingestion_parameters") unless (attributes.keys - allowed).empty?
      row = user.with_lock do
        row = ResearchIngestion.find_or_initialize_by(user: user, request_key: attributes.fetch(:request_key))
        expected = attributes.merge(space_id: space.id).stringify_keys
        if row.persisted?
          unless expected.all? { |name, value| row.public_send(name) == value }
            raise Error.new("idempotency_key_conflict")
          end
        else
          row.assign_attributes(attributes.merge(space: space))
          row.save!
        end
        row
      end
      ResearchIngestionJob.perform_later(row.id) if row.state == "pending"
      row
    end

    def initialize(request, policy_factory: ->(user) { Policy.new(user) }, source: nil, embedder: nil)
      @request = request
      @owner = request.user
      @space = request.space
      @policy_factory = policy_factory
      @source = source
      @embedder = embedder || Embedder.new(@space)
    end

    def call
      raise Error.new("database_transaction_open") if ApplicationRecord.connection.transaction_open?
      claim!
      return @request if @request.state == "ready"
      fetch! unless @request.source_revision
      chunk!
      embed!
      publish!
      @request.reload
    rescue Error => error
      fail!(error.code)
    rescue ActiveRecord::RecordNotFound
      fail!("source_deleted")
    rescue ActiveRecord::Encryption::Errors::Decryption, ActiveRecord::Encryption::Errors::Configuration
      fail!("equibles_credentials_unavailable")
    end

    private

    def policy
      @policy_factory.call(@owner).check!(@request)
    end

    def claim!
      @owner.with_lock do
        @request.reload
        approval = policy
        if @request.state == "ready"
          validate_document!(approval)
          revision
          return
        end
        raise Error.new("ingestion_busy_or_requires_resume") unless @request.state == "pending"
        if @request.document_id.nil?
          raise Error.new("source_deleted") if @request.document_generation
          source_id = "#{@request.listing_identity}/#{@request.fiscal_year}/Q#{@request.fiscal_quarter}"
          document = @owner.research_documents.find_or_initialize_by(
            provider: @request.provider, source_kind: @request.source_kind, source_id: source_id
          )
          if document.new_record?
            document.assign_attributes(instrument_identity: "#{@request.provider}:#{@request.listing_identity}",
              listing_identity: @request.listing_identity, fiscal_year: @request.fiscal_year,
              fiscal_period: "Q#{@request.fiscal_quarter}", citation_url: citation_url,
              entitlement_reference: approval.reference(@request), rights_expires_at: approval.deadline(@request))
            document.save!
          end
          @request.document = document
          validate_document!(approval)
          document.update!(ingestion_generation: document.ingestion_generation + 1)
          @request.document_generation = document.ingestion_generation
        else
          validate_document!(approval)
          raise Error.new("source_superseded") unless @request.document.ingestion_generation == @request.document_generation
        end
        if @request.provider == "equibles"
          raise Error.new("equibles_credentials_unavailable") unless EquiblesConnection.encryption_configured?
          connection = @owner.equibles_connection
          key = connection&.api_key.to_s.strip
          unless connection && key.present? && key.valid_encoding? && key.length <= 4096 && !key.match?(/\s/)
            raise Error.new("equibles_credentials_required")
          end
          fingerprint = credential_fingerprint(connection)
          if @request.credential_fingerprint && @request.credential_fingerprint != fingerprint
            raise Error.new("source_credentials_changed")
          end
          @request.credential_fingerprint = fingerprint
        end
        @token = SecureRandom.uuid
        @request.update!(state: "fetching", lease_token: @token, lease_expires_at: Time.current + 90.seconds,
                         document: @request.document, document_generation: @request.document_generation,
                         credential_fingerprint: @request.credential_fingerprint, error_code: nil)
      end
    end

    def citation_url
      return "https://example.test/original-alpha-earnings" if @request.provider == "synthetic"
      ticker = URI.encode_www_form_component(@request.listing_identity.delete_prefix("US:"))
      "https://api.equibles.com/v1/stocks/#{ticker}/earnings-calls/#{@request.fiscal_year}/#{@request.fiscal_quarter}"
    end

    def validate_document!(approval)
      raise Error.new("source_deleted") unless @request.document
      document = @request.document.reload
      if document.revoked_at || document.rights_expires_at <= Time.current
        raise Error.new("source_revoked_or_expired")
      end
      if document.entitlement_reference != approval.reference(@request)
        raise Error.new("source_approval_changed")
      end
    end

    def guard!
      @request.reload
      unless @request.lease_token == @token && @token && @request.lease_expires_at > Time.current &&
             !%w[ready failed pending].include?(@request.state)
        raise Error.new("stale_ingestion")
      end
      approval = policy
      validate_document!(approval)
      if @request.document.ingestion_generation != @request.document_generation
        raise Error.new("source_superseded")
      end
      if @request.provider == "equibles"
        connection = @owner.equibles_connection&.reload
        unless connection && credential_fingerprint(connection) == @request.credential_fingerprint
          raise Error.new("source_credentials_changed")
        end
      end
      approval
    end

    def guarded
      @owner.with_lock { yield guard! }
    end

    def remaining
      left = @request.lease_expires_at - Time.current
      raise Error.new("ingestion_deadline") unless left.positive?
      left
    end

    def credential_fingerprint(connection)
      Digest::SHA256.hexdigest(connection.read_attribute_before_type_cast(:api_key).to_s)
    end

    def reserve_source!
      guarded do |approval|
        SourceQuota.reserve!(@request, allocation: approval.settings.fetch("daily_source_requests"), limit: 3)
        remaining
      end
    end

    def fetch!
      guarded { }
      key = @request.provider == "equibles" ? @owner.equibles_connection.reload.api_key.to_s.strip : nil
      adapter = @source || (@request.provider == "synthetic" ? SyntheticSource.new : EquiblesSource.new)
      data = adapter.call(@request, before_request: -> { reserve_source! }, api_key: key)
      temporal = TemporalEvidence.source(data, provider: @request.provider)
      normalized = Chunker.normalize(data.fetch(:parts), metadata: data.fetch(:metadata).merge("source_temporal" => temporal[:fingerprint]),
                                     forbidden: [key, ENV["OPENAI_API_KEY"].to_s.strip])
      guarded do |approval|
        document = @request.document
        revision = document.revisions.find_or_initialize_by(source_revision: normalized.fetch(:source_revision))
        if revision.persisted?
          if revision.revoked_at || revision.expires_at <= Time.current || revision.superseded_at
            raise Error.new("revision_revoked_expired_or_superseded")
          end
          verified = data.fetch(:received_at)
          revision.update!(verified_at: verified,
            fresh_until: [verified + approval.freshness(@request), revision.expires_at, approval.deadline(@request)].min)
        else
          if ResearchIngestion.where(document_id: document.id, source_revision: normalized[:source_revision]).where.not(id: @request.id).exists?
            raise Error.new("previous_revision_deleted")
          end
          received = data.fetch(:received_at)
          expires = [received + approval.retention(@request), document.rights_expires_at, approval.deadline(@request)].min
          revision.assign_attributes(normalized.merge(temporal[:values]).merge(user: @owner,
            temporal_metadata: temporal[:metadata], verified_at: received,
            expires_at: expires, fresh_until: [received + approval.freshness(@request), expires].min))
          revision.save!
        end
        previous = document.current_revision
        if previous && previous.id != revision.id
          previous.update!(superseded_at: Time.current)
          document.update!(current_revision_id: nil)
        end
        document.purge_superseded!(keep_revision: revision) unless approval.history?(@request)
        @request.update!(source_revision: revision.source_revision, state: "chunking")
      end
    end

    def revision
      row = @request.document.revisions.find_by!(source_revision: @request.source_revision)
      if row.revoked_at || row.expires_at <= Time.current || row.superseded_at
        raise Error.new("revision_revoked_expired_or_superseded")
      end
      row
    end

    def chunk!
      row = revision
      parts = Chunker.new.call(row)
      guarded do
        row = revision
        parts.each do |attributes|
          passage = row.passages.find_or_initialize_by(preprocessing_version: @space.preprocessing_version,
            chunker_version: @space.chunker_version, position: attributes.fetch(:position))
          if passage.persisted?
            unless attributes.all? { |name, value| passage.public_send(name) == value }
              raise Error.new("chunk_provenance_mismatch")
            end
          else
            passage.assign_attributes(attributes.merge(user: @owner))
            passage.save!
          end
        end
        if passages(row).count != parts.size
          raise Error.new("chunk_provenance_mismatch")
        end
        row.update!(index_state: "pending") unless row.index_state == "ready"
        @request.update!(state: "embedding")
      end
    end

    def passages(row = revision)
      row.passages.where(preprocessing_version: @space.preprocessing_version, chunker_version: @space.chunker_version)
    end

    def embed!
      missing = passages.where.not(id: @space.embeddings.select(:passage_id)).order(:position).to_a
      missing.each_slice(4) do |batch|
        guarded { revision }
        @embedder.prepare!
        batch_key = Digest::SHA256.hexdigest(JSON.generate([@space.id, batch.map { |part| [part.id, part.checksum] }]))
        attempt = ResearchEmbeddingAttempt.reserve!(@request, tokens: batch.sum(&:token_count),
                                                    batch_key: batch_key, paid: @space.provider == "openai")
        guarded do
          revision
          if attempt.budget_date != Time.current.utc.to_date
            attempt.update!(state: "released")
            raise Error.new("embedding_budget_date_changed")
          end
          attempt.update!(state: "dispatched")
        end
        begin
          raise Error.new("database_transaction_open") if ApplicationRecord.connection.transaction_open?
          result = @embedder.call(batch, timeout: remaining, idempotency_key: "research-#{attempt.id}")
          attempt.reconcile!(tokens: result.tokens)
        rescue Error => error
          attempt.reconcile!(tokens: error.actual_tokens, error_code: error.code)
          raise
        end
        guarded do
          revision
          batch.zip(result.vectors).each do |part, vector|
            @space.embeddings.create!(user: @owner, passage: part, embedding: vector)
          end
        end
      end
    end

    def publish!
      guarded do |approval|
        row = revision
        eligible = passages(row)
        if !eligible.exists? || eligible.where.not(id: @space.embeddings.select(:passage_id)).exists?
          raise Error.new("indexing_incomplete")
        end
        document = @request.document
        previous = document.current_revision
        previous.update!(superseded_at: Time.current) if previous && previous.id != row.id
        row.update!(index_state: "ready", indexed_at: row.indexed_at || Time.current)
        document.update!(current_revision: row)
        document.purge_superseded! unless approval.history?(@request)
        @request.update!(state: "ready", lease_token: nil, lease_expires_at: nil, error_code: nil)
      end
    end

    def fail!(code)
      @owner.with_lock do
        row = ResearchIngestion.find_by(id: @request.id, user_id: @owner.id)
        if row && ((@token && row.lease_token == @token) || (!@token && %w[pending ready].include?(row.state)))
          row.update!(state: "failed", error_code: code, lease_token: nil, lease_expires_at: nil)
          row.embedding_attempts.where(state: "reserved").update_all(state: "released", error_code: code, updated_at: Time.current)
          if code == "research_permission_required" && row.document
            row.document.update!(revoked_at: Time.current)
          end
          if row.document && row.source_revision
            failed = row.document.revisions.find_by(source_revision: row.source_revision)
            failed.update!(index_state: "failed") if failed && failed.id != row.document.current_revision_id
          end
          @request = row
        else
          Rails.logger.warn("Research ingestion #{@request.id} rejected code=#{code}")
          raise Error.new(code)
        end
      end
      Rails.logger.warn("Research ingestion #{@request.id} failed code=#{code}")
      @request
    end
  end
end
