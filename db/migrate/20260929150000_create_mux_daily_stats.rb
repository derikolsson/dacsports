class CreateMuxDailyStats < ActiveRecord::Migration[8.0]
  def change
    # Mux Data per Chicago day, video, audience (custom_1) and stream type. event_id is
    # resolved from video_id at import time and stays null when nothing matches.
    create_table :mux_daily_stats do |t|
      t.date :day, null: false
      t.string :video_id, null: false
      t.bigint :event_id
      t.string :audience, null: false
      t.string :stream_type, null: false
      t.integer :views, null: false, default: 0
      t.integer :unique_viewers, null: false, default: 0
      t.bigint :watch_time_ms, null: false, default: 0
      t.timestamps
    end
    add_index :mux_daily_stats, [ :day, :video_id, :audience, :stream_type ], unique: true, name: "index_mux_daily_stats_unique"
    add_index :mux_daily_stats, [ :event_id, :day ]

    create_table :mux_daily_countries do |t|
      t.date :day, null: false
      t.string :audience, null: false
      t.string :country_code, null: false
      t.integer :views, null: false, default: 0
      t.bigint :watch_time_ms, null: false, default: 0
      t.timestamps
    end
    add_index :mux_daily_countries, [ :day, :audience, :country_code ], unique: true, name: "index_mux_daily_countries_unique"
  end
end
