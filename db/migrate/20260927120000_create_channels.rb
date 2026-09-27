class CreateChannels < ActiveRecord::Migration[8.0]
  def up
    create_table :channels do |t|
      t.string :name, null: false
      t.string :mux_live_stream_id
      t.string :mux_live_playback_id
      t.string :mux_live_signed_playback_id
      t.timestamps
    end
    add_index :channels, :mux_live_stream_id, unique: true

    add_column :events, :channel_id, :bigint
    add_index :events, :channel_id

    backfill_channels
  end

  def down
    remove_column :events, :channel_id
    drop_table :channels
  end

  private

  # Each Mux live stream shows up on events as a public/signed playback ID pair, sometimes
  # with one half missing. Pairs that share either ID are the same stream, so they fold
  # into one channel. The Mux live stream ID isn't known here; `rake mux:import_channels`
  # fills it in afterwards by matching these playback IDs.
  def backfill_channels
    rows = select_rows(<<~SQL)
      SELECT DISTINCT NULLIF(mux_live_playback_id, ''), NULLIF(mux_live_signed_playback_id, '')
      FROM events
      WHERE COALESCE(mux_live_playback_id, '') <> '' OR COALESCE(mux_live_signed_playback_id, '') <> ''
    SQL

    groups = []
    rows.each do |public_id, signed_id|
      group = groups.find { |g| (public_id && g[:public] == public_id) || (signed_id && g[:signed] == signed_id) }
      if group
        group[:public] ||= public_id
        group[:signed] ||= signed_id
      else
        groups << { public: public_id, signed: signed_id }
      end
    end

    groups.each.with_index(1) do |group, n|
      channel_id = select_value(<<~SQL)
        INSERT INTO channels (name, mux_live_playback_id, mux_live_signed_playback_id, created_at, updated_at)
        VALUES (#{quote("Channel #{n}")}, #{quote(group[:public])}, #{quote(group[:signed])}, NOW(), NOW())
        RETURNING id
      SQL

      execute(<<~SQL)
        UPDATE events SET channel_id = #{channel_id}
        WHERE mux_live_playback_id = #{quote(group[:public])}
           OR mux_live_signed_playback_id = #{quote(group[:signed])}
      SQL
    end
  end
end
