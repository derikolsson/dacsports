class AddPosterKeyToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :poster_key, :string
  end
end
