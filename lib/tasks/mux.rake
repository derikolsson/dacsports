namespace :mux do
  desc "Link every Mux live stream to a Channel, minting signed playback IDs (idempotent)"
  task import_channels: :environment do
    service = MuxSignedPlaybackId.new
    streams = MuxRuby::LiveStreamsApi.new.list_live_streams(limit: 100).data

    if streams.empty?
      puts "No live streams found in this Mux environment."
      next
    end

    streams.each do |stream|
      playback_ids = Array(stream.playback_ids).map(&:id)

      # Channels backfilled from events know the playback IDs but not the stream ID.
      channel = Channel.find_by(mux_live_stream_id: stream.id) ||
                Channel.where(mux_live_stream_id: nil)
                       .where(mux_live_playback_id: playback_ids)
                       .or(Channel.where(mux_live_stream_id: nil, mux_live_signed_playback_id: playback_ids))
                       .first ||
                Channel.new(name: stream.meta&.title.presence || stream.id)
      created = channel.new_record?

      channel.update!(mux_live_stream_id: stream.id)
      channel.sync_from_mux!

      puts "live stream #{stream.id} -> #{created ? 'new' : 'existing'} channel \"#{channel.name}\""
      puts "  status          : #{stream.status}"
      puts "  latency mode    : #{stream.latency_mode}"
      puts "  public playback : #{channel.mux_live_playback_id || 'none'}"
      puts "  signed playback : #{channel.mux_live_signed_playback_id}"
      puts "  events          : #{channel.events.count}"

      unless service.recordings_signed?(stream.id)
        puts "  WARNING: new_asset_settings.playback_policies does not include 'signed'."
        puts "           Mux does not allow changing this after creation, so recordings"
        puts "           from this stream arrive public-only. Paste the asset ID on the"
        puts "           event and the app will mint a signed playback ID for it."
      end
    end

    unlinked = Channel.where(mux_live_stream_id: nil)
    if unlinked.any?
      puts "\nWARNING: these channels matched no Mux stream: #{unlinked.pluck(:name).join(', ')}"
    end

    puts "\nDone. Existing public playback IDs were left in place — the on-site player"
    puts "still depends on them. Do not delete them until on-site signing ships."
  end

  desc "Resolve or create the signed playback ID for a Mux asset: rake mux:sign_asset[ASSET_ID]"
  task :sign_asset, [ :asset_id ] => :environment do |_t, args|
    abort "Usage: rake mux:sign_asset[ASSET_ID]" if args[:asset_id].blank?
    puts MuxSignedPlaybackId.for_asset(args[:asset_id])
  end

  desc "Verify the signing key in credentials matches one present in the Mux environment"
  task verify_signing_key: :environment do
    unless MuxTokenSigner.configured?
      abort "mux.signing_key_id / mux.signing_key_private are not both set in credentials."
    end

    local  = MuxTokenSigner.credentials[:signing_key_id]
    remote = MuxRuby::SigningKeysApi.new.list_signing_keys(limit: 100).data.map(&:id)

    if remote.include?(local)
      puts "OK: signing key #{local} is present in this Mux environment."
    else
      abort "MISMATCH: credentials signing key #{local} is not in this environment " \
            "(found: #{remote.join(', ').presence || 'none'}). Signing would fail with an opaque 403."
    end
  end
end
