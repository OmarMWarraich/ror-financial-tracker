class GuardResearchAgentIdentity < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL
      CREATE FUNCTION research_agent_identity_guard() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF ROW(NEW.user_id, NEW.request_key, NEW.query_digest, NEW.selectors, NEW.provider,
               NEW.model, NEW.prompt_version, NEW.deadline_at)
          IS DISTINCT FROM ROW(OLD.user_id, OLD.request_key, OLD.query_digest, OLD.selectors,
               OLD.provider, OLD.model, OLD.prompt_version, OLD.deadline_at)
          OR (OLD.credential_fingerprints <> '{}'::jsonb AND NEW.credential_fingerprints IS DISTINCT FROM OLD.credential_fingerprints)
        THEN
          RAISE EXCEPTION 'research agent request identity is immutable';
        END IF;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER research_agent_identity_immutable BEFORE UPDATE ON research_agent_runs
        FOR EACH ROW EXECUTE FUNCTION research_agent_identity_guard();
    SQL
    add_check_constraint :research_agent_runs,
      "(provider = 'fixture' AND model = 'original-fixture-v1') OR (provider = 'openai' AND model = 'gpt-5.4-mini-2026-03-17')",
      name: "research_agent_provider_model"
    execute <<~SQL
      CREATE FUNCTION research_retrieval_agent_guard() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF OLD.agent_run_id IS NOT NULL AND NEW.agent_run_id IS DISTINCT FROM OLD.agent_run_id THEN
          RAISE EXCEPTION 'research retrieval agent association is immutable';
        END IF;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER research_retrieval_agent_immutable BEFORE UPDATE ON research_retrievals
        FOR EACH ROW EXECUTE FUNCTION research_retrieval_agent_guard();
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Preserve immutable agent identity and accounting associations"
  end
end
