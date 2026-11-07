class AddResearchAgentReceipts < ActiveRecord::Migration[7.1]
  def up
    create_table :research_agent_runs do |t|
      t.references :user, null: false, foreign_key: true
      t.string :request_key, null: false
      t.string :query_digest, null: false
      t.jsonb :selectors, null: false
      t.jsonb :credential_fingerprints, null: false, default: {}
      t.string :provider, null: false
      t.string :model, null: false
      t.string :prompt_version, null: false
      t.string :state, null: false, default: "running"
      t.integer :source_requests, null: false, default: 0
      t.integer :tool_calls, null: false, default: 0
      t.datetime :deadline_at, null: false
      t.string :error_code
      t.timestamps
    end
    add_index :research_agent_runs, [:id, :user_id], unique: true
    add_index :research_agent_runs, [:user_id, :request_key], unique: true
    add_check_constraint :research_agent_runs,
      "query_digest ~ '^[0-9a-f]{64}$' AND request_key <> '' AND provider IN ('openai','fixture') AND state IN ('running','completed','no_evidence','failed','cancelled') AND source_requests BETWEEN 0 AND 16 AND tool_calls BETWEEN 0 AND 6 AND jsonb_typeof(selectors) = 'object' AND jsonb_typeof(credential_fingerprints) = 'object'",
      name: "research_agent_run_contract"

    create_table :research_model_attempts do |t|
      t.references :user, null: false, foreign_key: true
      t.references :run, null: false
      t.integer :step, null: false
      t.date :budget_date, null: false
      t.string :state, null: false, default: "reserved"
      t.integer :reserved_input_tokens, null: false
      t.integer :reserved_output_tokens, null: false
      t.bigint :reserved_cost_nanos, null: false
      t.integer :actual_input_tokens
      t.integer :actual_output_tokens
      t.bigint :actual_cost_nanos
      t.string :error_code
      t.timestamps
    end
    add_index :research_model_attempts, [:run_id, :step], unique: true
    add_foreign_key :research_model_attempts, :research_agent_runs,
      column: [:run_id, :user_id], primary_key: [:id, :user_id]
    add_check_constraint :research_model_attempts,
      "step BETWEEN 1 AND 4 AND state IN ('reserved','dispatched','settled','uncertain','released') AND reserved_input_tokens BETWEEN 1 AND 10000 AND reserved_output_tokens BETWEEN 1 AND 4096 AND reserved_cost_nanos >= 0 AND (actual_input_tokens IS NULL OR actual_input_tokens >= 0) AND (actual_output_tokens IS NULL OR actual_output_tokens >= 0) AND (actual_cost_nanos IS NULL OR actual_cost_nanos >= 0)",
      name: "research_model_attempt_contract"
    add_column :research_retrievals, :agent_run_id, :bigint
    add_foreign_key :research_retrievals, :research_agent_runs,
      column: [:agent_run_id, :user_id], primary_key: [:id, :user_id]
    add_index :research_retrievals, :agent_run_id
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Preserve agent audit and shared usage receipts"
  end
end
