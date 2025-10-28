class AddSportToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :sport, :string
  end
end
