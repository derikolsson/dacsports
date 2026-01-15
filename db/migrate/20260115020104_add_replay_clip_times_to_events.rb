class AddReplayClipTimesToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :replay_start_time, :decimal, precision: 10, scale: 2
    add_column :events, :replay_end_time, :decimal, precision: 10, scale: 2
  end
end
