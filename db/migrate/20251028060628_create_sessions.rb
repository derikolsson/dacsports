class CreateSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :sessions, id: :uuid do |t|
      t.uuid :visitor_id, null: false
      t.timestamp :last_seen_at
      t.string :user_agent
      t.string :browser_name
      t.string :os_name
      t.string :device_type

      t.timestamps
    end

    add_index :sessions, :visitor_id
  end
end
