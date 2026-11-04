# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2026_11_05_043000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "broker_connections", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "label", null: false
    t.string "product", default: "exchange", null: false
    t.string "mode", default: "read_only", null: false
    t.string "state", default: "pending", null: false
    t.string "key_fingerprint", null: false
    t.text "api_key"
    t.text "api_secret"
    t.text "account_identifier"
    t.text "balance_payload"
    t.text "history_payload"
    t.jsonb "verified_permissions", default: [], null: false
    t.boolean "include_history", default: false, null: false
    t.bigint "last_nonce", default: 0, null: false
    t.datetime "expires_at", null: false
    t.datetime "last_attempt_at"
    t.datetime "received_at"
    t.datetime "disconnected_at"
    t.string "last_error"
    t.string "elevation_state", default: "not_requested", null: false
    t.datetime "elevation_requested_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key_fingerprint"], name: "index_broker_connections_on_key_fingerprint", unique: true
    t.index ["user_id"], name: "index_broker_connections_on_user_id"
    t.check_constraint "mode::text = 'read_only'::text", name: "broker_monitoring_only"
    t.check_constraint "product::text = 'exchange'::text", name: "broker_exchange_only"
  end

  create_table "equibles_connections", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.text "api_key"
    t.jsonb "snapshot", default: {}, null: false
    t.date "quota_date"
    t.integer "requests_used", default: 0, null: false
    t.datetime "last_attempt_at"
    t.datetime "last_success_at"
    t.string "last_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_equibles_connections_on_user_id", unique: true
    t.check_constraint "requests_used >= 0", name: "equibles_nonnegative_usage"
  end

  create_table "friendships", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "friend_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["friend_id"], name: "index_friendships_on_friend_id"
    t.index ["user_id"], name: "index_friendships_on_user_id"
  end

  create_table "stocks", force: :cascade do |t|
    t.string "ticker"
    t.string "name"
    t.decimal "last_price"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "user_stocks", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "stock_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["stock_id"], name: "index_user_stocks_on_stock_id"
    t.index ["user_id"], name: "index_user_stocks_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "first_name"
    t.string "last_name"
    t.integer "sensitive_action_failures", default: 0, null: false
    t.datetime "sensitive_action_locked_until"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "broker_connections", "users"
  add_foreign_key "equibles_connections", "users"
  add_foreign_key "friendships", "users"
  add_foreign_key "friendships", "users", column: "friend_id"
  add_foreign_key "user_stocks", "stocks"
  add_foreign_key "user_stocks", "users"
end
