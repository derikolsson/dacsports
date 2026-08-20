namespace :mux do
  desc "Add signed playback IDs to the Mux live streams (idempotent)"
  task provision_live_streams: :environment do
    service = MuxSignedPlaybackId.new
    streams = MuxRuby::LiveStreamsApi.new.list_live_streams(limit: 100).data

    if streams.empty?
      puts "No live streams found in this Mux environment."
      next
    end

    streams.each do |stream|
      signed_id = service.for_live_stream(stream.id)
      policies  = Array(stream.playback_ids).map { |p| p.policy.to_s }.uniq.sort

      puts "live stream #{stream.id}"
      puts "  status          : #{stream.status}"
      puts "  playback IDs    : #{policies.join(', ')}"
      puts "  signed playback : #{signed_id}"

      unless service.recordings_signed?(stream.id)
        puts "  WARNING: new_asset_settings.playback_policies does not include 'signed'."
        puts "           Mux does not allow changing this after creation, so recordings"
        puts "           from this stream arrive public-only. Paste the asset ID on the"
        puts "           event and the app will mint a signed playback ID for it."
      end
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

    MuxSignedPlaybackId.configure!
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
