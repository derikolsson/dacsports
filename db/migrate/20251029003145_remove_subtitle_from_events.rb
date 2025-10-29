class RemoveSubtitleFromEvents < ActiveRecord::Migration[8.0]
  def change
    remove_column :events, :subtitle, :string
  end
end
