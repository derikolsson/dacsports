class RemoveSeedFromEventTeams < ActiveRecord::Migration[8.0]
  def change
    remove_column :event_teams, :seed, :integer
  end
end
