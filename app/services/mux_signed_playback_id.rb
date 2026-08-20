# Resolves (or creates) the signed playback ID for a Mux live stream or asset.
#
# Idempotent: if a signed playback ID already exists on the resource it is returned
# as-is rather than minting a second one. Safe to re-run.
#
# Adding a signed playback ID does NOT disable an existing public one — the public URL
# keeps working until that playback ID is explicitly deleted. That is deliberate here:
# the on-site player still plays off the public IDs.
class MuxSignedPlaybackId
  SIGNED = MuxRuby::PlaybackPolicy::SIGNED

  class Error < StandardError; end

  def self.configure!
    MuxRuby.configure do |config|
      config.username = Rails.application.credentials.dig(:mux, :token_id)
      config.password = Rails.application.credentials.dig(:mux, :token_secret)
    end
  end

  def self.for_live_stream(live_stream_id)
    new.for_live_stream(live_stream_id)
  end

  def self.for_asset(asset_id)
    new.for_asset(asset_id)
  end

  def initialize
    self.class.configure!
  end

  def for_live_stream(live_stream_id)
    raise ArgumentError, "live_stream_id is required" if live_stream_id.blank?

    api = MuxRuby::LiveStreamsApi.new
    stream = api.get_live_stream(live_stream_id).data
    existing = signed_id_from(stream.playback_ids)
    return existing if existing

    api.create_live_stream_playback_id(live_stream_id, signed_request).data.id
  rescue MuxRuby::ApiError => e
    raise Error, "Mux live stream #{live_stream_id}: #{e.message}"
  end

  def for_asset(asset_id)
    raise ArgumentError, "asset_id is required" if asset_id.blank?

    api = MuxRuby::AssetsApi.new
    asset = api.get_asset(asset_id).data
    existing = signed_id_from(asset.playback_ids)
    return existing if existing

    api.create_asset_playback_id(asset_id, signed_request).data.id
  rescue MuxRuby::ApiError => e
    raise Error, "Mux asset #{asset_id}: #{e.message}"
  end

  # Reports whether recordings born from this live stream will come out signed.
  #
  # NOTE: this is read-only on purpose. Mux's PATCH /live-streams endpoint documents
  # that of new_asset_settings "only the mp4_support, master_access, and video_quality
  # settings may be updated" — playback_policies is fixed at live stream creation time
  # and cannot be flipped afterward. Both existing DAC streams were created
  # ["public"], so every recording arrives public-only and needs a signed playback ID
  # minted individually via #for_asset. That is the operator's paste-the-asset-ID flow.
  #
  # The only way to change this is to create a replacement live stream with
  # playback_policies: ["public", "signed"], which issues a NEW stream key and means
  # reconfiguring the encoder at the venue. Worth doing next time stream config is
  # touched anyway; not worth an unprompted mid-season disruption.
  def recordings_signed?(live_stream_id)
    stream = MuxRuby::LiveStreamsApi.new.get_live_stream(live_stream_id).data
    Array(stream.new_asset_settings&.playback_policies).map(&:to_s).include?(SIGNED)
  rescue MuxRuby::ApiError => e
    raise Error, "Mux live stream #{live_stream_id}: #{e.message}"
  end

  private

  def signed_request
    MuxRuby::CreatePlaybackIDRequest.new(policy: SIGNED)
  end

  def signed_id_from(playback_ids)
    Array(playback_ids).find { |p| p.policy.to_s == SIGNED }&.id
  end
end
