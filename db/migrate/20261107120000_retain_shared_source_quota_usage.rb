class RetainSharedSourceQuotaUsage < ActiveRecord::Migration[7.1]
  def up
    create_table :research_source_usages do |t|
      t.references :user, foreign_key: { on_delete: :nullify }
      t.references :connection, foreign_key: { to_table: :equibles_connections, on_delete: :nullify }
      t.string :key_digest, null: false
      t.date :budget_date, null: false
      t.integer :requests_used, null: false
    end
    add_index :research_source_usages, [:connection_id, :key_digest, :budget_date], unique: true,
      name: "research_source_usage_identity"
    add_index :research_source_usages, [:key_digest, :budget_date]
    add_check_constraint :research_source_usages, "key_digest ~ '^[0-9a-f]{64}$' AND requests_used >= 0",
      name: "research_source_usage_contract"
    execute <<~SQL
      INSERT INTO research_source_usages (user_id, connection_id, key_digest, budget_date, requests_used)
      SELECT user_id, id, quota_key_digest, quota_date, requests_used FROM equibles_connections
      WHERE quota_key_digest IS NOT NULL AND quota_date IS NOT NULL AND requests_used > 0;
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Retain already-consumed shared provider capacity"
  end
end
