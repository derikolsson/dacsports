class AddSignedPlaybackToEventsAndVisits < ActiveRecord::Migration[8.0]
  def change
    # Signed playback IDs are distinct IDs from the existing public ones. The public
    # ones stay in place — the on-site player still depends on them.
    add_column :events, :mux_live_signed_playback_id, :string
    add_column :events, :mux_replay_signed_playback_id, :string

    # What the operator pastes once VOD is ready; the signed replay playback ID is
    # resolved from it.
    add_column :events, :mux_asset_id, :string

    # "dsn" = DAC Sports Network's own site. Embeds carry their own partner value.
    add_column :event_visits, :source, :string, null: false, default: "dsn"
    add_column :event_visits, :referrer_origin, :string

    # An embed visit and an on-site visit from one session are distinct visits, so
    # source has to participate in the uniqueness constraint.
    remove_index :event_visits, name: "index_event_visits_unique_session_event"
    add_index :event_visits,
              [ :session_id, :event_id, :event_status, :source ],
              unique: true,
              name: "index_event_visits_unique_session_event_source"
  end
end
