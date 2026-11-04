class CreateEquiblesConnections < ActiveRecord::Migration[7.1]
  def change
    create_table :equibles_connections do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.text :api_key
      t.jsonb :snapshot, null: false, default: {}
      t.date :quota_date
      t.integer :requests_used, null: false, default: 0
      t.datetime :last_attempt_at
      t.datetime :last_success_at
      t.string :last_error
      t.timestamps
    end
    add_check_constraint :equibles_connections, "requests_used >= 0", name: "equibles_nonnegative_usage"
  end
end
