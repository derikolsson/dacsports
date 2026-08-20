# Signs Mux playback JWTs.
#
# This is the only place in the app that touches the Mux signing key. The private key
# stays server-side and is never rendered into markup or exposed to the client.
#
# Mux binds a playback restriction to the *token*, not to the playback ID — the
# `playback_restriction_id` claim is what scopes a token to a set of allowed referrers.
# That is why the restriction is an argument: one signed playback ID can be served to
# the district embeds under restriction A and (later) to our own pages under B, with
# only this claim differing.
class MuxTokenSigner
  # Mux calls these "audiences": v=video, t=thumbnail, s=storyboard.
  AUDIENCE_VIDEO      = "v".freeze
  AUDIENCE_THUMBNAIL  = "t".freeze
  AUDIENCE_STORYBOARD = "s".freeze

  # A signed URL stops playing the moment it expires, even mid-playback, and Mux has no
  # mechanism to rotate a token without tearing down the source. Mux disconnects
  # continuous streams at ~12h, so a 12h token cannot under-cover a stream that is able
  # to exist. Tokens are re-signed on every page load, so the long lifetime is free.
  DEFAULT_EXPIRY = 12.hours

  class MissingSigningKey < StandardError; end

  def initialize(playback_restriction_id: nil, expires_in: DEFAULT_EXPIRY)
    @playback_restriction_id = playback_restriction_id
    @expires_in = expires_in
  end

  # Returns { playback:, thumbnail:, storyboard: } — storyboard is nil for live, since
  # Mux only generates storyboards for on-demand assets.
  def tokens_for(playback_id, live: false)
    {
      playback: sign(playback_id, AUDIENCE_VIDEO),
      thumbnail: sign(playback_id, AUDIENCE_THUMBNAIL),
      storyboard: live ? nil : sign(playback_id, AUDIENCE_STORYBOARD)
    }
  end

  def sign(playback_id, audience)
    raise ArgumentError, "playback_id is required" if playback_id.blank?

    claims = {
      sub: playback_id,
      aud: audience,
      exp: @expires_in.from_now.to_i,
      kid: signing_key_id
    }
    claims[:playback_restriction_id] = @playback_restriction_id if @playback_restriction_id.present?

    JWT.encode(claims, private_key, "RS256", { kid: signing_key_id })
  end

  def self.configured?
    credentials[:signing_key_id].present? && credentials[:signing_key_private].present?
  end

  def self.credentials
    Rails.application.credentials.mux || {}
  end

  private

  def signing_key_id
    @signing_key_id ||= self.class.credentials[:signing_key_id].presence ||
                        raise(MissingSigningKey, "mux.signing_key_id is not set in credentials")
  end

  # Mux hands the private key back base64-encoded at creation time.
  def private_key
    @private_key ||= begin
      encoded = self.class.credentials[:signing_key_private].presence ||
                raise(MissingSigningKey, "mux.signing_key_private is not set in credentials")
      OpenSSL::PKey::RSA.new(Base64.decode64(encoded))
    end
  end
end
