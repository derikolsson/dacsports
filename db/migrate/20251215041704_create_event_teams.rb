class CreateEventTeams < ActiveRecord::Migration[8.0]
  def change
    create_table :event_teams do |t|
      t.references :event, null: false, foreign_key: true
      t.references :team, null: false, foreign_key: true
      t.integer :seed

      t.timestamps
    end

    add_index :event_teams, [ :event_id, :team_id ], unique: true
  end
end
