class AddResearchChatSessionsAndSources < ActiveRecord::Migration[7.1]
  def up
    create_table :research_chat_sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.string :authentication_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :research_chat_sessions, :token_digest, unique: true
    add_column :research_messages, :sources, :jsonb, null: false, default: []
    add_check_constraint :research_messages, "jsonb_typeof(sources) = 'array' AND jsonb_array_length(sources) <= 6",
      name: "research_message_sources_contract"
    execute <<~SQL
      CREATE OR REPLACE FUNCTION research_message_identity_guard() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF ROW(NEW.user_id, NEW.conversation_id, NEW.run_id, NEW.role, NEW.expires_at)
          IS DISTINCT FROM ROW(OLD.user_id, OLD.conversation_id, OLD.run_id, OLD.role, OLD.expires_at)
          OR (ROW(NEW.content, NEW.source_ids, NEW.sources, NEW.state)
            IS DISTINCT FROM ROW(OLD.content, OLD.source_ids, OLD.sources, OLD.state)
            AND NOT (NEW.state = 'redacted' AND NEW.content IS NULL AND NEW.source_ids = '[]'::jsonb AND NEW.sources = '[]'::jsonb))
        THEN RAISE EXCEPTION 'research message identity is immutable except redaction'; END IF;
        RETURN NEW;
      END;
      $$;
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Preserve research chat ownership and source audit"
  end
end
