# A short-lived, signed permission to view one event's live stream through /embed/:slug
# before the event is live.
#
# The embed route deliberately ignores ?preview=true: it is framed on partner pages,
# and anything a plain param can unlock, a partner page can unlock too. A pass is only
# ever minted here, on request from the internal preview page, and is bound to a single
# slug — so a district cannot be talked into one, and one leaked pass cannot be
# repointed at another event.
class EmbedPreviewPass
  PURPOSE = :embed_preview
  TTL = 30.minutes

  def self.generate(event)
    verifier.generate(event.slug, purpose: PURPOSE, expires_in: TTL)
  end

  # True only for an unexpired pass minted for exactly this event.
  def self.valid?(token, event)
    return false if token.blank? || event.nil?

    verifier.verified(token.to_s, purpose: PURPOSE) == event.slug
  end

  def self.verifier
    Rails.application.message_verifier(:embed_preview)
  end
end
