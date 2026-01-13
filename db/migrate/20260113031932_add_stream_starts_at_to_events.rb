class AddStreamStartsAtToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :stream_starts_at, :datetime
  end
end
