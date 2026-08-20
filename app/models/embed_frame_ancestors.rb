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

  attr_accessor :raw

  validate :every_origin_is_valid

  def self.current
    new(raw: read_redis)
  end

  def self.read_redis
    Dacsports.redis.get(REDIS_KEY)
  rescue Redis::BaseError, Errno::ECONNREFUSED
    nil
  end

  # What the header actually gets. 'none' when nothing is configured, so the route stays
  # closed until somebody deliberately opens it.
  def self.header_value
    stored = read_redis.presence
    stored || "'none'"
  end

  def origins
    raw.to_s.split(/[\s,]+/).map(&:strip).reject(&:blank?)
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
    true
  end

  private

  def every_origin_is_valid
    if origins.size > MAX_ORIGINS
      errors.add(:base, "Too many entries (limit #{MAX_ORIGINS}).")
      return
    end

    origins.each do |origin|
      next if origin.match?(ORIGIN_FORMAT)

      errors.add(:base, "#{origin.truncate(60)} is not a valid origin. " \
                        "Use a full origin such as https://athletics.example.org, " \
                        "optionally with a single wildcard label (https://*.example.org).")
    end
  end
end
