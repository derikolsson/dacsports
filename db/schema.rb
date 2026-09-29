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

ActiveRecord::Schema[8.0].define(version: 2026_09_29_150000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "channels", force: :cascade do |t|
    t.string "name", null: false
    t.string "mux_live_stream_id"
    t.string "mux_live_playback_id"
    t.string "mux_live_signed_playback_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "captions_enabled", default: false, null: false
    t.datetime "captions_synced_at"
    t.string "captions_sync_error"
    t.index ["mux_live_stream_id"], name: "index_channels_on_mux_live_stream_id", unique: true
  end

  create_table "event_slugs", force: :cascade do |t|
    t.bigint "event_id", null: false
    t.string "slug", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_event_slugs_on_event_id"
    t.index ["slug"], name: "index_event_slugs_on_slug", unique: true
  end

  create_table "event_teams", force: :cascade do |t|
    t.bigint "event_id", null: false
    t.bigint "team_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id", "team_id"], name: "index_event_teams_on_event_id_and_team_id", unique: true
    t.index ["event_id"], name: "index_event_teams_on_event_id"
    t.index ["team_id"], name: "index_event_teams_on_team_id"
  end

  create_table "event_visits", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "session_id", null: false
    t.bigint "event_id", null: false
    t.string "event_status", null: false
    t.datetime "started_at", precision: nil
    t.datetime "last_seen_at", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "source", default: "dsn", null: false
    t.string "referrer_origin"
    t.datetime "first_played_at"
    t.string "page_url"
    t.string "page_title"
    t.string "host_referrer_origin"
    t.string "utm_source"
    t.string "utm_medium"
    t.string "utm_campaign"
    t.index ["event_id"], name: "index_event_visits_on_event_id"
    t.index ["first_played_at"], name: "index_event_visits_on_first_played_at"
    t.index ["last_seen_at"], name: "index_event_visits_on_last_seen_at"
    t.index ["session_id", "event_id", "event_status", "source"], name: "index_event_visits_unique_session_event_source", unique: true
    t.index ["session_id"], name: "index_event_visits_on_session_id"
    t.index ["source", "started_at"], name: "index_event_visits_on_source_and_started_at"
  end

  create_table "events", force: :cascade do |t|
    t.string "title", null: false
    t.string "slug", null: false
    t.datetime "start_at", null: false
    t.string "time_zone", default: "America/Chicago", null: false
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
    t.datetime "stream_starts_at"
    t.string "mux_replay_playback_id"
    t.decimal "replay_start_time", precision: 10, scale: 2
    t.decimal "replay_end_time", precision: 10, scale: 2
    t.string "mux_replay_signed_playback_id"
    t.string "mux_asset_id"
    t.bigint "channel_id"
    t.index ["channel_id"], name: "index_events_on_channel_id"
    t.index ["slug"], name: "index_events_on_slug", unique: true
  end

  create_table "mux_daily_countries", force: :cascade do |t|
    t.date "day", null: false
    t.string "audience", null: false
    t.string "country_code", null: false
    t.integer "views", default: 0, null: false
    t.bigint "watch_time_ms", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["day", "audience", "country_code"], name: "index_mux_daily_countries_unique", unique: true
  end

  create_table "mux_daily_stats", force: :cascade do |t|
    t.date "day", null: false
    t.string "video_id", null: false
    t.bigint "event_id"
    t.string "audience", null: false
    t.string "stream_type", null: false
    t.integer "views", default: 0, null: false
    t.integer "unique_viewers", default: 0, null: false
    t.bigint "watch_time_ms", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["day", "video_id", "audience", "stream_type"], name: "index_mux_daily_stats_unique", unique: true
    t.index ["event_id", "day"], name: "index_mux_daily_stats_on_event_id_and_day"
  end

  create_table "passkeys", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "external_id", null: false
    t.string "public_key", null: false
    t.bigint "sign_count", default: 0, null: false
    t.string "name", null: false
    t.datetime "last_used_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["external_id"], name: "index_passkeys_on_external_id", unique: true
    t.index ["user_id"], name: "index_passkeys_on_user_id"
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
    t.string "landing_referrer_host"
    t.string "landing_path"
    t.string "utm_source"
    t.string "utm_medium"
    t.string "utm_campaign"
    t.index ["visitor_id"], name: "index_sessions_on_visitor_id"
  end

  create_table "teams", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_teams_on_slug", unique: true
  end

  create_table "user_sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_user_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "name"
    t.string "password_digest"
    t.boolean "admin", default: false, null: false
    t.bigint "invited_by_id"
    t.datetime "invitation_accepted_at"
    t.datetime "deactivated_at"
    t.datetime "last_signed_in_at"
    t.string "webauthn_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["webauthn_id"], name: "index_users_on_webauthn_id", unique: true
  end

  create_table "vocabularies", force: :cascade do |t|
    t.bigint "channel_id"
    t.text "phrases", default: "", null: false
    t.string "mux_vocabulary_id"
    t.datetime "synced_at"
    t.string "sync_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["channel_id"], name: "index_vocabularies_on_channel_id", unique: true, nulls_not_distinct: true
  end

  add_foreign_key "event_slugs", "events"
  add_foreign_key "event_teams", "events"
  add_foreign_key "event_teams", "teams"
end
