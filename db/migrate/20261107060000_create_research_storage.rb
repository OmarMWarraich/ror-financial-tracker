class CreateResearchStorage < ActiveRecord::Migration[7.1]
  def up
    enable_extension "vector"
    unless select_value("SELECT extversion FROM pg_extension WHERE extname = 'vector'") == "0.8.1"
      raise "Research storage requires the reviewed pgvector 0.8.1 installation"
    end

    create_table :research_documents do |t|
      t.references :user, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :source_kind, null: false
      t.string :source_id, null: false
      t.string :instrument_identity, null: false
      t.string :listing_identity, null: false
      t.integer :fiscal_year, null: false
      t.string :fiscal_period, null: false
      t.string :citation_url, null: false
      t.string :entitlement_reference, null: false
      t.datetime :rights_expires_at, null: false
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :research_documents, [:id, :user_id], unique: true
    add_index :research_documents, [:user_id, :provider, :source_kind, :source_id],
              unique: true, name: "research_document_source"
    add_index :research_documents, [:user_id, :listing_identity, :fiscal_year, :fiscal_period],
              name: "research_document_period"
    add_check_constraint :research_documents,
                         "provider <> '' AND source_id <> '' AND instrument_identity <> '' AND listing_identity <> '' AND entitlement_reference <> '' AND citation_url ~ '^https://[^[:space:]]+$' AND fiscal_year > 0 AND fiscal_period IN ('Q1','Q2','Q3','Q4','FY') AND source_kind IN ('earnings_brief','earnings_transcript','filing')",
                         name: "research_document_identity"

    create_table :research_revisions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :document, null: false
      t.string :source_revision, null: false
      t.text :content, null: false
      t.string :checksum, null: false
      t.datetime :event_at
      t.datetime :published_at
      t.datetime :known_at
      t.datetime :received_at, null: false
      t.datetime :indexed_at
      t.datetime :fresh_until
      t.datetime :expires_at, null: false
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :research_revisions, [:id, :user_id], unique: true
    add_index :research_revisions, [:document_id, :source_revision], unique: true
    add_index :research_revisions, [:user_id, :known_at]
    add_index :research_revisions, :expires_at
    add_foreign_key :research_revisions, :research_documents,
                    column: [:document_id, :user_id], primary_key: [:id, :user_id]
    add_check_constraint :research_revisions,
                         "source_revision <> '' AND content <> '' AND checksum = encode(sha256(convert_to(content, 'UTF8')), 'hex') AND expires_at > received_at AND (fresh_until IS NULL OR fresh_until <= expires_at)",
                         name: "research_revision_content_and_lifetime"

    create_table :research_passages do |t|
      t.references :user, null: false, foreign_key: true
      t.references :revision, null: false
      t.string :preprocessing_version, null: false
      t.string :chunker_version, null: false
      t.integer :position, null: false
      t.integer :start_char, null: false
      t.integer :end_char, null: false
      t.integer :start_line
      t.integer :end_line
      t.string :speaker
      t.integer :token_count, null: false
      t.text :content, null: false
      t.string :checksum, null: false
      t.timestamps
    end
    add_index :research_passages, [:revision_id, :preprocessing_version, :chunker_version, :position],
              unique: true, name: "research_passage_position"
    add_index :research_passages, [:id, :user_id, :checksum, :preprocessing_version, :chunker_version],
              unique: true, name: "research_passage_identity"
    add_foreign_key :research_passages, :research_revisions,
                    column: [:revision_id, :user_id], primary_key: [:id, :user_id]
    add_check_constraint :research_passages,
                         "preprocessing_version <> '' AND chunker_version <> '' AND position >= 0 AND start_char >= 0 AND end_char > start_char AND end_char - start_char = char_length(content) AND token_count > 0 AND token_count <= 800 AND checksum = encode(sha256(convert_to(content, 'UTF8')), 'hex') AND ((start_line IS NULL AND end_line IS NULL) OR (start_line IS NOT NULL AND end_line IS NOT NULL AND start_line > 0 AND end_line >= start_line))",
                         name: "research_passage_content_and_position"

    create_table :research_embedding_spaces do |t|
      t.references :user, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :model, null: false
      t.string :model_version, null: false
      t.integer :dimensions, null: false, default: 1536
      t.string :distance, null: false, default: "cosine"
      t.string :preprocessing_version, null: false
      t.string :chunker_version, null: false
      t.string :state, null: false, default: "building"
      t.timestamps
    end
    add_index :research_embedding_spaces, [:id, :user_id, :preprocessing_version, :chunker_version],
              unique: true, name: "research_space_identity"
    add_index :research_embedding_spaces, [:user_id, :provider, :model, :model_version, :preprocessing_version, :chunker_version],
              unique: true, name: "research_space_version"
    add_index :research_embedding_spaces, :user_id, unique: true, where: "state = 'active'",
              name: "one_active_research_space"
    add_check_constraint :research_embedding_spaces,
                         "provider <> '' AND model <> '' AND model_version <> '' AND preprocessing_version <> '' AND chunker_version <> '' AND dimensions = 1536 AND distance = 'cosine' AND state IN ('building','active','retired')",
                         name: "research_space_contract"

    create_table :research_embeddings do |t|
      t.references :user, null: false, foreign_key: true
      t.references :passage, null: false
      t.references :space, null: false
      t.string :preprocessing_version, null: false
      t.string :chunker_version, null: false
      t.string :input_checksum, null: false
      t.column :embedding, :vector, limit: 1536, null: false
      t.timestamps
    end
    add_index :research_embeddings, [:space_id, :passage_id], unique: true
    add_foreign_key :research_embeddings, :research_passages,
                    column: [:passage_id, :user_id, :input_checksum, :preprocessing_version, :chunker_version],
                    primary_key: [:id, :user_id, :checksum, :preprocessing_version, :chunker_version]
    add_foreign_key :research_embeddings, :research_embedding_spaces,
                    column: [:space_id, :user_id, :preprocessing_version, :chunker_version],
                    primary_key: [:id, :user_id, :preprocessing_version, :chunker_version]
    add_check_constraint :research_embeddings, "vector_norm(embedding) > 0",
                         name: "research_embedding_nonzero"

    execute <<~SQL
      CREATE FUNCTION research_space_preserve_identity() RETURNS trigger AS $$
      BEGIN
        IF ROW(NEW.user_id, NEW.provider, NEW.model, NEW.model_version, NEW.dimensions,
               NEW.distance, NEW.preprocessing_version, NEW.chunker_version)
           IS DISTINCT FROM
           ROW(OLD.user_id, OLD.provider, OLD.model, OLD.model_version, OLD.dimensions,
               OLD.distance, OLD.preprocessing_version, OLD.chunker_version) THEN
          RAISE EXCEPTION 'Embedding space identity is immutable; create a new version';
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
      CREATE TRIGGER research_space_identity_immutable BEFORE UPDATE ON research_embedding_spaces
        FOR EACH ROW EXECUTE FUNCTION research_space_preserve_identity();
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "Preserve research data and vector extension; use the documented application rollback or an isolated restore"
  end
end
