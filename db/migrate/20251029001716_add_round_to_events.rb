class AddRoundToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :round, :string
  end
end
