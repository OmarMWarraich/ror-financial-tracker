class AddResearchIngestion < ActiveRecord::Migration[7.1]
  def up
    add_column :research_documents, :current_revision_id, :bigint
    add_column :research_documents, :ingestion_generation, :integer, null: false, default: 0
    add_column :research_revisions, :index_state, :string, null: false, default: "pending"
    add_column :research_revisions, :source_metadata, :jsonb, null: false, default: {}
    add_column :research_revisions, :superseded_at, :datetime
    add_column :research_passages, :source_metadata, :jsonb, null: false, default: {}
    add_index :research_revisions, [:id, :document_id, :user_id], unique: true,
              name: "research_revision_document_identity"
    add_foreign_key :research_documents, :research_revisions,
                    column: [:current_revision_id, :id, :user_id], primary_key: [:id, :document_id, :user_id]
    add_check_constraint :research_revisions, "index_state IN ('pending','ready','failed')",
                         name: "research_revision_index_state"
    add_check_constraint :research_documents, "ingestion_generation >= 0",
                         name: "research_document_generation"

    create_table :research_ingestions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :space, null: false
      t.bigint :document_id
      t.string :request_key, null: false
      t.string :provider, null: false
      t.string :source_kind, null: false
      t.string :listing_identity, null: false
      t.integer :fiscal_year, null: false
      t.integer :fiscal_quarter, null: false
      t.string :fixture_version
      t.string :source_revision
      t.string :state, null: false, default: "pending"
      t.integer :generation, null: false, default: 0
      t.integer :document_generation
      t.string :lease_token
      t.datetime :lease_expires_at
      t.string :credential_fingerprint
      t.integer :source_requests, null: false, default: 0
      t.string :error_code
      t.timestamps
    end
    add_index :research_embedding_spaces, [:id, :user_id], unique: true
    add_index :research_ingestions, [:id, :user_id], unique: true
    add_index :research_ingestions, [:user_id, :request_key], unique: true
    add_foreign_key :research_ingestions, :research_documents,
                    column: [:document_id, :user_id], primary_key: [:id, :user_id]
    add_foreign_key :research_ingestions, :research_embedding_spaces,
                    column: [:space_id, :user_id], primary_key: [:id, :user_id]
    add_check_constraint :research_ingestions,
                         "state IN ('pending','fetching','chunking','embedding','ready','failed') AND provider IN ('synthetic','equibles') AND source_kind IN ('earnings_transcript','earnings_brief') AND fiscal_year BETWEEN 1900 AND 2200 AND fiscal_quarter BETWEEN 1 AND 4 AND generation >= 0 AND source_requests BETWEEN 0 AND 3 AND request_key <> ''",
                         name: "research_ingestion_contract"

    create_table :research_embedding_attempts do |t|
      t.references :user, null: false, foreign_key: true
      t.references :ingestion, null: false
      t.string :batch_key, null: false
      t.integer :generation, null: false
      t.date :budget_date, null: false
      t.string :state, null: false, default: "reserved"
      t.integer :reserved_tokens, null: false
      t.bigint :reserved_cost_nanos, null: false
      t.integer :actual_tokens
      t.bigint :actual_cost_nanos
      t.string :error_code
      t.timestamps
    end
    add_index :research_embedding_attempts, [:ingestion_id, :generation, :batch_key],
              unique: true, name: "research_embedding_batch_attempt"
    add_index :research_embedding_attempts, [:budget_date, :user_id]
    add_foreign_key :research_embedding_attempts, :research_ingestions,
                    column: [:ingestion_id, :user_id], primary_key: [:id, :user_id]
    add_check_constraint :research_embedding_attempts,
                         "state IN ('reserved','dispatched','settled','uncertain','released') AND reserved_tokens BETWEEN 1 AND 3200 AND reserved_cost_nanos >= 0 AND (actual_tokens IS NULL OR actual_tokens >= 0) AND (actual_cost_nanos IS NULL OR actual_cost_nanos >= 0)",
                         name: "research_embedding_attempt_budget"
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Preserve ingestion provenance, budget receipts and vector storage"
  end
end
