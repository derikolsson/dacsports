# The partner page allow-list for the embed route's CSP frame-ancestors directive.
#
# Stored in Redis rather than credentials or a migration so partner URLs can be added
# the moment the department sends them, without a deploy. Matches how event_status_ttl
# and keepalive_timeout are already handled.
#
# Everything here is written verbatim into a response header, so entries are validated
# strictly: a stray semicolon or newline would let someone append their own CSP
# directives and disable protections on the page.
class EmbedFrameAncestors
  include ActiveModel::Model

  REDIS_KEY = "embed_frame_ancestors".freeze
  ALLOW_SELF_KEY = "embed_frame_ancestors_allow_self".freeze

  # scheme://host, an optional single leading wildcard label, and an optional port.
  # Wildcards cover one label only — *.example.com does not match a.b.example.com — so
  # apex and wildcard have to be listed separately, same as the Mux restriction.
  ORIGIN_FORMAT = %r{
    \A
    https?://
    (\*\.)?
    (?!-)[a-z0-9-]+(?<!-)
    (\.(?!-)[a-z0-9-]+(?<!-))*
    (:\d{1,5})?
    \z
  }xi

  MAX_ORIGINS = 50
  MAX_ORIGIN_LENGTH = 253  # DNS limit; also keeps the header from bloating

  attr_accessor :raw
  attr_writer :allow_self

  validate :every_origin_is_valid

  def self.current
    new(raw: read_redis, allow_self: allow_self?)
  end

  # Whether our own site may frame the player. On by default because the internal
  # preview page needs it; turn it off for a genuinely closed posture, at the cost of
  # the preview.
  def self.allow_self?
    Dacsports.redis.get(ALLOW_SELF_KEY) != "false"
  rescue Redis::BaseError, Errno::ECONNREFUSED
    true
  end

  def self.read_redis
    Dacsports.redis.get(REDIS_KEY)
  rescue Redis::BaseError, Errno::ECONNREFUSED
    nil
  end

  # What the header actually gets.
  #
  # 'self' is always included so our own internal preview page can frame the embed and
  # confirm it works before anyone is told it does. It grants nothing meaningful — an
  # attacker able to serve a page on dacsports.net has better options than framing us —
  # and partners stay blocked until they are listed explicitly.
  SELF = "'self'".freeze

  def self.header_value
    parts = []
    parts << SELF if allow_self?
    parts << read_redis.presence
    parts.compact!

    # Never emit an empty directive — that would be treated as malformed and could be
    # ignored entirely, which fails open.
    parts.any? ? parts.join(" ") : "'none'"
  end

  def origins
    raw.to_s.split(/[\s,]+/).map(&:strip).reject(&:blank?).uniq
  end

  def allow_self?
    ActiveModel::Type::Boolean.new.cast(@allow_self) != false
  end

  def blocked?
    origins.empty?
  end

  def save
    return false unless valid?

    if origins.empty?
      Dacsports.redis.del(REDIS_KEY)
    else
      Dacsports.redis.set(REDIS_KEY, origins.join(" "))
    end

    Dacsports.redis.set(ALLOW_SELF_KEY, allow_self?.to_s)
    true
  end

  private

  def every_origin_is_valid
    if origins.size > MAX_ORIGINS
      errors.add(:base, "Too many entries (limit #{MAX_ORIGINS}).")
      return
    end

    origins.each do |origin|
      if origin.length > MAX_ORIGIN_LENGTH
        errors.add(:base, "#{origin.truncate(60)} is too long to be a hostname.")
        next
      end

      unless origin.match?(ORIGIN_FORMAT)
        errors.add(:base, "#{origin.truncate(60)} is not a valid origin. " \
                          "Use a full origin such as https://athletics.example.org, " \
                          "optionally with a single wildcard label (https://*.example.org).")
        next
      end

      port = origin[/:(\d+)\z/, 1]
      next if port.nil? || port.to_i.between?(1, 65_535)

      errors.add(:base, "#{origin.truncate(60)} has an invalid port.")
    end
  end
end
