class AddDurableResearchLifecycle < ActiveRecord::Migration[7.1]
  def up
    create_table :research_conversations do |t|
      t.references :user, null: false, foreign_key: true
      t.jsonb :scope, null: false
      t.jsonb :limits, null: false
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_index :research_conversations, [:id, :user_id], unique: true
    add_column :research_agent_runs, :conversation_id, :bigint
    add_foreign_key :research_agent_runs, :research_conversations, column: [:conversation_id, :user_id], primary_key: [:id, :user_id]
    add_index :research_agent_runs, :conversation_id
    add_column :research_agent_runs, :limits, :jsonb, null: false, default: {}
    add_column :research_agent_runs, :pricing, :jsonb, null: false, default: {}
    add_column :research_agent_runs, :workflow_version, :string
    add_column :research_agent_runs, :budget_date, :date
    add_column :research_agent_runs, :reserved_cost_nanos, :bigint, null: false, default: 0
    add_column :research_agent_runs, :reserved_source_requests, :integer, null: false, default: 0
    add_column :research_agent_runs, :cancel_requested_at, :datetime
    add_column :research_agent_runs, :lease_token, :string
    add_column :research_agent_runs, :lease_until, :datetime
    add_column :research_agent_runs, :enqueued_at, :datetime
    add_column :research_agent_runs, :enqueue_attempts, :integer, null: false, default: 0
    add_column :research_agent_runs, :finished_at, :datetime
    remove_check_constraint :research_agent_runs, name: "research_agent_run_contract"
    add_check_constraint :research_agent_runs,
      "query_digest ~ '^[0-9a-f]{64}$' AND request_key <> '' AND provider IN ('openai','fixture') AND state IN ('queued','running','completed','no_evidence','failed','cancelled','interrupted') AND source_requests BETWEEN 0 AND 16 AND tool_calls BETWEEN 0 AND 6 AND jsonb_typeof(selectors) = 'object' AND jsonb_typeof(credential_fingerprints) = 'object' AND jsonb_typeof(limits) = 'object' AND jsonb_typeof(pricing) = 'object' AND reserved_cost_nanos BETWEEN 0 AND 50000000 AND reserved_source_requests BETWEEN 0 AND 16 AND (conversation_id IS NULL OR (budget_date IS NOT NULL AND workflow_version IS NOT NULL))",
      name: "research_agent_run_contract"
    create_table :research_messages do |t|
      t.references :user, null: false, foreign_key: true
      t.bigint :conversation_id, null: false
      t.bigint :run_id, null: false
      t.string :role, null: false
      t.string :state, null: false
      t.text :content
      t.jsonb :source_ids, null: false, default: []
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_foreign_key :research_messages, :research_conversations, column: [:conversation_id, :user_id], primary_key: [:id, :user_id]
    add_foreign_key :research_messages, :research_agent_runs, column: [:run_id, :user_id], primary_key: [:id, :user_id]
    add_index :research_messages, [:run_id, :role], unique: true
    add_index :research_agent_runs, [:id, :conversation_id, :user_id], unique: true, name: "research_run_conversation_owner"
    add_foreign_key :research_messages, :research_agent_runs, column: [:run_id, :conversation_id, :user_id],
      primary_key: [:id, :conversation_id, :user_id], name: "research_message_run_conversation"
    add_check_constraint :research_messages,
      "role IN ('user','assistant') AND state IN ('submitted','complete','incomplete','redacted') AND jsonb_typeof(source_ids) = 'array'",
      name: "research_message_contract"
    create_table :research_tool_attempts do |t|
      t.references :user, null: false, foreign_key: true
      t.bigint :run_id, null: false
      t.string :call_id, null: false
      t.string :name, null: false
      t.string :arguments_digest, null: false
      t.string :state, null: false
      t.string :source_id
      t.string :error_code
      t.timestamps
    end
    add_foreign_key :research_tool_attempts, :research_agent_runs, column: [:run_id, :user_id], primary_key: [:id, :user_id]
    add_index :research_tool_attempts, [:run_id, :call_id], unique: true
    add_check_constraint :research_tool_attempts,
      "name IN ('GetEarningsCallEvent','GetEarningsBrief','GetEarningsCallTranscript') AND arguments_digest ~ '^[0-9a-f]{64}$' AND state IN ('dispatched','settled','cached','failed','uncertain')",
      name: "research_tool_attempt_contract"
    add_column :equibles_connections, :quota_observation, :jsonb, null: false, default: {}
    add_column :equibles_connections, :quota_key_digest, :string
    add_index :equibles_connections, :quota_key_digest
    add_column :research_agent_runs, :source_connection_id, :bigint
    add_index :equibles_connections, [:id, :user_id], unique: true
    add_foreign_key :research_agent_runs, :equibles_connections, column: [:source_connection_id, :user_id], primary_key: [:id, :user_id]
    execute <<~SQL
      CREATE FUNCTION research_durable_identity_guard() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF ROW(NEW.conversation_id, NEW.limits, NEW.pricing, NEW.workflow_version, NEW.budget_date,
               NEW.reserved_cost_nanos, NEW.reserved_source_requests, NEW.source_connection_id)
          IS DISTINCT FROM ROW(OLD.conversation_id, OLD.limits, OLD.pricing, OLD.workflow_version, OLD.budget_date,
               OLD.reserved_cost_nanos, OLD.reserved_source_requests, OLD.source_connection_id)
          OR (OLD.state <> NEW.state AND NOT (
            (OLD.state = 'queued' AND NEW.state IN ('running','failed','cancelled','interrupted')) OR
            (OLD.state = 'running' AND NEW.state IN ('completed','no_evidence','failed','cancelled','interrupted'))))
        THEN RAISE EXCEPTION 'research durable run identity or transition is invalid'; END IF;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER research_durable_identity BEFORE UPDATE ON research_agent_runs
        FOR EACH ROW EXECUTE FUNCTION research_durable_identity_guard();
      CREATE FUNCTION research_conversation_identity_guard() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF ROW(NEW.user_id, NEW.scope, NEW.limits, NEW.expires_at)
          IS DISTINCT FROM ROW(OLD.user_id, OLD.scope, OLD.limits, OLD.expires_at)
        THEN RAISE EXCEPTION 'research conversation identity is immutable'; END IF;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER research_conversation_identity BEFORE UPDATE ON research_conversations
        FOR EACH ROW EXECUTE FUNCTION research_conversation_identity_guard();
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Preserve durable chat and usage receipts"
  end
end
