class CreateBrokerConnections < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :sensitive_action_failures, :integer, null: false, default: 0
    add_column :users, :sensitive_action_locked_until, :datetime
    create_table :broker_connections do |t|
      t.references :user, null: false, foreign_key: true
      t.string :label, null: false
      t.string :product, null: false, default: "exchange"
      t.string :mode, null: false, default: "read_only"
      t.string :state, null: false, default: "pending"
      t.string :key_fingerprint, null: false
      t.text :api_key
      t.text :api_secret
      t.text :account_identifier
      t.text :balance_payload
      t.text :history_payload
      t.jsonb :verified_permissions, null: false, default: []
      t.boolean :include_history, null: false, default: false
      t.bigint :last_nonce, null: false, default: 0
      t.datetime :expires_at, null: false
      t.datetime :last_attempt_at
      t.datetime :received_at
      t.datetime :disconnected_at
      t.string :last_error
      t.string :elevation_state, null: false, default: "not_requested"
      t.datetime :elevation_requested_at
      t.timestamps
    end
    add_index :broker_connections, :key_fingerprint, unique: true
    add_check_constraint :broker_connections, "mode = 'read_only'", name: "broker_monitoring_only"
    add_check_constraint :broker_connections, "product = 'exchange'", name: "broker_exchange_only"
  end
end
