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

ActiveRecord::Schema[8.0].define(version: 2025_10_30_011451) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "event_slugs", force: :cascade do |t|
    t.bigint "event_id", null: false
    t.string "slug", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_event_slugs_on_event_id"
    t.index ["slug"], name: "index_event_slugs_on_slug", unique: true
  end

  create_table "event_visits", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "session_id", null: false
    t.bigint "event_id", null: false
    t.string "event_status", null: false
    t.datetime "started_at", precision: nil
    t.datetime "last_seen_at", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_event_visits_on_event_id"
    t.index ["session_id"], name: "index_event_visits_on_session_id"
  end

  create_table "events", force: :cascade do |t|
    t.string "title", null: false
    t.string "slug", null: false
    t.datetime "start_at", null: false
    t.string "time_zone", default: "America/Chicago", null: false
    t.text "live_embed_code"
    t.text "replay_embed_code"
    t.string "status", default: "upcoming", null: false
    t.boolean "visible", default: true
    t.integer "force_reload_count", default: 0
    t.string "short_name"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "sport"
    t.string "location"
    t.string "round"
    t.index ["slug"], name: "index_events_on_slug", unique: true
  end

  create_table "sessions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "visitor_id", null: false
    t.datetime "last_seen_at", precision: nil
    t.string "user_agent"
    t.string "browser_name"
    t.string "os_name"
    t.string "device_type"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["visitor_id"], name: "index_sessions_on_visitor_id"
  end

  add_foreign_key "event_slugs", "events"
end
