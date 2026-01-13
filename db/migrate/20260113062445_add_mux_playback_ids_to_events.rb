class AddMuxPlaybackIdsToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :mux_live_playback_id, :string
    add_column :events, :mux_replay_playback_id, :string
  end
end
