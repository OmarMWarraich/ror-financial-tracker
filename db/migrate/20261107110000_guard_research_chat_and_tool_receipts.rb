class GuardResearchChatAndToolReceipts < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL
      CREATE FUNCTION research_message_identity_guard() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF ROW(NEW.user_id, NEW.conversation_id, NEW.run_id, NEW.role, NEW.expires_at)
          IS DISTINCT FROM ROW(OLD.user_id, OLD.conversation_id, OLD.run_id, OLD.role, OLD.expires_at)
          OR (ROW(NEW.content, NEW.source_ids, NEW.state)
            IS DISTINCT FROM ROW(OLD.content, OLD.source_ids, OLD.state)
            AND NOT (NEW.state = 'redacted' AND NEW.content IS NULL AND NEW.source_ids = '[]'::jsonb))
        THEN RAISE EXCEPTION 'research message identity is immutable except redaction'; END IF;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER research_message_identity BEFORE UPDATE ON research_messages
        FOR EACH ROW EXECUTE FUNCTION research_message_identity_guard();
      CREATE FUNCTION research_tool_identity_guard() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF ROW(NEW.user_id, NEW.run_id, NEW.call_id, NEW.name, NEW.arguments_digest)
          IS DISTINCT FROM ROW(OLD.user_id, OLD.run_id, OLD.call_id, OLD.name, OLD.arguments_digest)
        THEN RAISE EXCEPTION 'research tool receipt identity is immutable'; END IF;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER research_tool_identity BEFORE UPDATE ON research_tool_attempts
        FOR EACH ROW EXECUTE FUNCTION research_tool_identity_guard();
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Preserve durable chat and tool audit identities"
  end
end
