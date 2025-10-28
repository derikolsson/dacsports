class CreateEventVisits < ActiveRecord::Migration[8.0]
  def change
    create_table :event_visits do |t|
      t.uuid :session_id, null: false
      t.bigint :event_id, null: false
      t.string :event_status, null: false
      t.timestamp :started_at
      t.timestamp :last_seen_at

      t.timestamps
    end

    add_index :event_visits, :session_id
    add_index :event_visits, :event_id
  end
end
