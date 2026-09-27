class RemoveLivePlaybackIdsFromEvents < ActiveRecord::Migration[8.0]
  def change
    remove_column :events, :mux_live_playback_id, :string
    remove_column :events, :mux_live_signed_playback_id, :string
  end
end
