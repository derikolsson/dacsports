class CreateEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :events do |t|
      t.string :title, null: false
      t.string :slug, null: false
      t.string :subtitle
      t.date :event_date, null: false
      t.datetime :start_at
      t.string :time_zone, null: false, default: 'America/Chicago'
      t.text :live_embed_code
      t.text :replay_embed_code
      t.string :status, null: false, default: 'upcoming'
      t.boolean :visible, default: true
      t.integer :force_reload_count, default: 0
      t.string :short_name
      t.text :description

      t.timestamps
    end

    add_index :events, :slug, unique: true
  end
end
