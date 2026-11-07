class AddResearchRetrieval < ActiveRecord::Migration[7.1]
  def up
    add_column :research_revisions, :temporal_metadata, :jsonb, null: false, default: {}
    add_check_constraint :research_revisions, "jsonb_typeof(temporal_metadata) = 'object'",
                         name: "research_temporal_metadata_object"
    execute <<~SQL
      ALTER TABLE research_passages ADD COLUMN search_vector tsvector
        GENERATED ALWAYS AS (to_tsvector('english'::regconfig, content)) STORED;
    SQL
    add_index :research_passages, :search_vector, using: :gin

    create_table :research_retrievals do |t|
      t.references :user, null: false, foreign_key: true
      t.references :space, null: false
      t.string :request_key, null: false
      t.string :query_digest, null: false
      t.jsonb :selectors, null: false
      t.jsonb :latest_event, null: false, default: {}
      t.jsonb :selection, null: false, default: []
      t.string :state, null: false, default: "pending"
      t.integer :generation, null: false, default: 0
      t.integer :source_requests, null: false, default: 0
      t.string :credential_fingerprint
      t.string :error_code
      t.datetime :deadline_at, null: false
      t.timestamps
    end
    add_index :research_retrievals, [:id, :user_id], unique: true
    add_index :research_retrievals, [:user_id, :request_key], unique: true
    add_foreign_key :research_retrievals, :research_embedding_spaces,
                    column: [:space_id, :user_id], primary_key: [:id, :user_id]
    add_check_constraint :research_retrievals,
      "request_key <> '' AND query_digest ~ '^[0-9a-f]{64}$' AND generation >= 0 AND source_requests BETWEEN 0 AND 2 AND state IN ('pending','retrieving','ready','no_evidence','stale_only','failed') AND jsonb_typeof(selectors) = 'object' AND jsonb_typeof(latest_event) = 'object' AND jsonb_typeof(selection) = 'array'",
      name: "research_retrieval_contract"

    change_column_null :research_embedding_attempts, :ingestion_id, true
    add_column :research_embedding_attempts, :retrieval_id, :bigint
    add_index :research_embedding_attempts, [:retrieval_id, :generation, :batch_key],
              unique: true, name: "research_query_embedding_attempt"
    add_foreign_key :research_embedding_attempts, :research_retrievals,
                    column: [:retrieval_id, :user_id], primary_key: [:id, :user_id]
    add_check_constraint :research_embedding_attempts,
                         "(ingestion_id IS NULL) <> (retrieval_id IS NULL)",
                         name: "research_embedding_attempt_owner_request"
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Preserve temporal evidence, full-text storage and usage receipts"
  end
end
