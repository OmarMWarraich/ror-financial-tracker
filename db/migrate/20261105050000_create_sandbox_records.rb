class CreateSandboxRecords < ActiveRecord::Migration[7.1]
  def change
    create_table :sandbox_accounts do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :environment, null: false, default: "synthetic"
      t.string :currency, null: false, default: "USD"
      t.decimal :initial_cash, precision: 14, scale: 2, null: false
      t.decimal :cash, precision: 14, scale: 2, null: false
      t.integer :quantity, null: false, default: 0
      t.decimal :cost_basis, precision: 14, scale: 2, null: false, default: 0
      t.string :fixture_key, null: false
      t.datetime :fixture_loaded_at, null: false
      t.timestamps
    end
    add_check_constraint :sandbox_accounts,
                         "environment = 'synthetic' AND currency = 'USD' AND initial_cash > 0 AND initial_cash <= 10000 AND cash >= 0 AND quantity >= 0 AND cost_basis >= 0",
                         name: "sandbox_account_bounds"

    create_table :sandbox_mandates do |t|
      t.references :sandbox_account, null: false, foreign_key: true
      t.string :state, null: false, default: "draft"
      t.string :rule_version, null: false, default: "trend-v1"
      t.string :instrument, null: false, default: "SYNTH-ALPHA"
      t.string :environment, null: false, default: "synthetic"
      t.string :session, null: false, default: "fixture"
      t.string :order_type, null: false, default: "synthetic_market"
      t.decimal :capital_limit, precision: 14, scale: 2, null: false
      t.decimal :max_notional, precision: 14, scale: 2, null: false
      t.integer :max_quantity, null: false
      t.decimal :max_exposure, precision: 14, scale: 2, null: false
      t.decimal :loss_limit, precision: 14, scale: 2, null: false
      t.datetime :expires_at, null: false
      t.datetime :approved_at
      t.timestamps
    end
    add_check_constraint :sandbox_mandates,
                         "state IN ('draft','active','paused','revoked') AND capital_limit > 0 AND capital_limit <= 10000 AND max_notional > 0 AND max_notional <= capital_limit AND max_quantity > 0 AND max_quantity <= 100 AND max_exposure > 0 AND max_exposure <= capital_limit AND loss_limit > 0 AND loss_limit <= capital_limit",
                         name: "sandbox_mandate_bounds"
    add_index :sandbox_mandates, :sandbox_account_id, unique: true,
              where: "state = 'active'", name: "one_active_sandbox_mandate"

    create_table :sandbox_orders do |t|
      t.references :sandbox_account, null: false, foreign_key: true
      t.references :sandbox_mandate, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :request_key, null: false
      t.string :fixture_key, null: false
      t.string :fixture_digest, null: false
      t.string :side, null: false
      t.string :state, null: false
      t.integer :quantity, null: false
      t.decimal :price, precision: 14, scale: 2, null: false
      t.decimal :fee, precision: 14, scale: 2, null: false
      t.decimal :reserved_cash, precision: 14, scale: 2, null: false
      t.integer :reserved_quantity, null: false
      t.datetime :created_at, null: false
    end
    add_index :sandbox_orders, [:user_id, :request_key], unique: true
    add_check_constraint :sandbox_orders,
                         "state = 'filled' AND side IN ('buy','sell') AND quantity > 0 AND price > 0 AND fee >= 0 AND reserved_cash >= 0 AND reserved_quantity >= 0",
                         name: "sandbox_order_bounds"

    create_table :sandbox_events do |t|
      t.references :sandbox_account, null: false, foreign_key: true
      t.string :kind, null: false
      t.jsonb :details, null: false, default: {}
      t.datetime :created_at, null: false
    end

    reversible do |dir|
      dir.up do
        execute <<~SQL
          CREATE FUNCTION sandbox_reject_mutation() RETURNS trigger AS $$
          BEGIN
            RAISE EXCEPTION 'Synthetic ledger rows are append-only';
          END;
          $$ LANGUAGE plpgsql;
          CREATE TRIGGER sandbox_events_immutable BEFORE UPDATE OR DELETE ON sandbox_events
            FOR EACH ROW EXECUTE FUNCTION sandbox_reject_mutation();
          CREATE TRIGGER sandbox_orders_immutable BEFORE UPDATE OR DELETE ON sandbox_orders
            FOR EACH ROW EXECUTE FUNCTION sandbox_reject_mutation();
        SQL
      end
      dir.down do
        execute "DROP TRIGGER sandbox_events_immutable ON sandbox_events"
        execute "DROP TRIGGER sandbox_orders_immutable ON sandbox_orders"
        execute "DROP FUNCTION sandbox_reject_mutation()"
      end
    end
  end
end
