module Research
  class TemporalPolicy
    LATEST_TTL = 15.minutes
    QUOTE_TTL = 120.seconds

    def self.fresh?(kind, event_at:, fresh_until:, now:, latest_observed_at: nil)
      case kind
      when "quote" then event_at && event_at <= now && event_at + QUOTE_TTL > now
      when "latest_earnings" then latest_observed_at && latest_observed_at <= now && latest_observed_at + LATEST_TTL > now
      when "earnings_brief", "earnings_transcript" then fresh_until && fresh_until > now
      when "filing", "company_fact" then true
      else raise Error.new("unsupported_relevance_policy")
      end
    end

    def self.revisions(mode:, now:, cutoff: nil, fresh: true)
      rows = ResearchRevision.where(revoked_at: nil, index_state: "ready")
        .where("research_revisions.expires_at > ? AND research_revisions.received_at <= ? AND research_revisions.indexed_at <= ?", now, now, now)
      bound = mode == "as_of" ? cutoff : now
      %w[event_at published_at known_at].each do |field|
        rows = rows.where("research_revisions.#{field} IS NULL OR research_revisions.#{field} <= ?", bound)
      end
      if mode == "as_of"
        # All observed versions must have a knowability basis; receipt/supersession cannot prove a revision timeline.
        rows.where("research_revisions.known_at <= ?", cutoff)
          .where("research_revisions.temporal_metadata #>> '{known_at,confidence}' = 'confirmed'")
          .where("research_revisions.temporal_metadata #>> '{known_at,basis}' IN (?)", TemporalEvidence::KNOWN_BASES)
          .where("research_revisions.known_at = (research_revisions.temporal_metadata #>> '{known_at,utc}')::timestamp")
          .where(<<~SQL, cutoff: cutoff)
            NOT EXISTS (
              SELECT 1 FROM research_revisions peer
              WHERE peer.document_id = research_revisions.document_id
                AND (peer.known_at IS NULL
                  OR COALESCE(peer.temporal_metadata #>> '{known_at,confidence}', '') <> 'confirmed'
                  OR COALESCE(peer.temporal_metadata #>> '{known_at,basis}', '') NOT IN ('original_fixture','source_revision_publication')
                  OR peer.known_at IS DISTINCT FROM (peer.temporal_metadata #>> '{known_at,utc}')::timestamp
                  OR (peer.id <> research_revisions.id AND peer.known_at <= :cutoff
                      AND peer.known_at >= research_revisions.known_at))
            )
          SQL
      else
        rows = rows.where(superseded_at: nil).where(id: ResearchDocument.select(:current_revision_id))
        if fresh && mode == "current"
          rows = rows.where("research_documents.source_kind = 'filing' OR research_revisions.fresh_until > ?", now)
        end
        rows
      end
    end
  end
end
