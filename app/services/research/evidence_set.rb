module Research
  class EvidenceSet
    attr_reader :request

    def initialize(retriever, display_only: false)
      @retriever = retriever
      @request = retriever.request
      @selection = @request.selection.deep_dup
      @display_only = display_only
    end

    def self.restore!(request, display_only: false)
      Retriever.restore(request, display_only: display_only)
    end

    def status
      @request.state
    end

    def reason
      @request.error_code
    end

    def context_json
      recheck!
      @retriever.context_for(@selection)
    end

    def recheck!
      @retriever.guarded do
        raise Error.new("no_evidence_for_dispatch") unless @request.state == "ready" && @selection.present?
        @retriever.context_for(@selection)
      end
      self
    end

    def check_request!
      @retriever.guarded { }
      self
    end

    def dispatch!(publisher:, &model_call)
      raise Error.new("display_evidence_cannot_dispatch") if @display_only
      raise Error.new("database_transaction_open") if ApplicationRecord.connection.transaction_open?
      raise Error.new("invalid_dispatch_callbacks") unless publisher.respond_to?(:call) && model_call
      context = context_json
      response = model_call.call(context)
      @retriever.guarded do
        @request.space.lock!
        @request.user.equibles_connection&.lock! if @request.selectors["provider"] == "equibles"
        ids = @selection.map { |item| item.fetch("passage_id") }
        passages = ResearchPassage.where(id: ids, user_id: @request.user_id).lock.to_a
        ResearchRevision.where(id: passages.map(&:revision_id)).lock.load
        ResearchDocument.where(id: passages.map { |part| part.revision.document_id }).lock.load
        recheck!
        publisher.call(response)
      end
    rescue Error => error
      Rails.logger.warn("Research evidence dispatch #{@request.id} rejected code=#{error.code}; already transmitted data cannot be recalled")
      raise
    end

    def self.fingerprint(passage)
      revision = passage.revision
      document = revision.document
      Digest::SHA256.hexdigest(JSON.generate([
        passage.attributes.except("search_vector", "created_at", "updated_at"),
        revision.attributes.except("content", "created_at", "updated_at"),
        document.attributes.except("created_at", "updated_at")
      ]))
    end

    def self.source(passage)
      revision = passage.revision
      document = revision.document
      { "source_id" => document.source_id, "document_id" => document.id, "revision_id" => revision.id,
        "source_revision" => revision.source_revision, "passage_id" => passage.id, "checksum" => passage.checksum,
        "provider" => document.provider, "source_kind" => document.source_kind,
        "instrument_identity" => document.instrument_identity, "listing_identity" => document.listing_identity,
        "fiscal_year" => document.fiscal_year, "fiscal_period" => document.fiscal_period,
        "citation_url" => document.citation_url, "content" => passage.content,
        "start_line" => passage.start_line, "end_line" => passage.end_line,
        "start_char" => passage.start_char, "end_char" => passage.end_char,
        "speaker" => passage.speaker, "speaker_role" => passage.source_metadata["speaker_role"],
        "section" => passage.source_metadata["section"], "turn_index" => passage.source_metadata["turn_index"],
        "start_seconds" => passage.source_metadata["start_seconds"], "end_seconds" => passage.source_metadata["end_seconds"],
        "dates" => TemporalEvidence.describe(revision), "synthetic" => document.provider == "synthetic",
        "uncertainty" => { "publication_unknown" => revision.published_at.nil?, "knowability_unknown" => revision.known_at.nil?,
                           "speaker_unknown" => passage.speaker.nil?, "instrument_is_presentation_identity" => true },
        "correction_count" => Array(revision.source_metadata["corrections"]).size }
    end
  end
end
