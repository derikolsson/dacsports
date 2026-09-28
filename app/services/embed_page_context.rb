# The partner page an embed was loaded on, from the values embed.js passes through the
# iframe URL (src, title, ref).
#
# All three are set by whoever controls the parent page, so nothing is trusted that
# can't be checked: the page URL is kept only when its origin matches the partner
# origin we saw in the Referer, its query string is reduced to UTM tags, and the
# parent's own referrer is reduced to an origin.
class EmbedPageContext
  UTM_KEYS = %w[utm_source utm_medium utm_campaign].freeze
  MAX_LENGTH = 255

  def self.from(src:, title:, ref:, partner_origin:)
    new(src, title, ref, partner_origin).to_h
  end

  def initialize(src, title, ref, partner_origin)
    @page = parse(src)
    @page = nil unless @page && partner_origin.present? && origin_of(@page) == partner_origin
    @title = title
    @ref = parse(ref)
  end

  # { "page_url" =>, "page_title" =>, "host_referrer_origin" =>, "utm_source" =>, ... },
  # only the keys we actually know. String keys, since it travels through a signed
  # token and a Sidekiq job.
  def to_h
    return {} unless @page

    {
      "page_url" => clip(page_url),
      "page_title" => clip(@title.to_s.squish.presence),
      "host_referrer_origin" => (origin_of(@ref) if @ref && origin_of(@ref) != origin_of(@page))
    }.merge(utm).compact
  end

  private

  def page_url
    kept = utm.map { |key, value| "#{key}=#{CGI.escape(value)}" }.join("&")
    "#{origin_of(@page)}#{@page.path.presence || "/"}#{"?#{kept}" if kept.present?}"
  end

  def utm
    @utm ||= URI.decode_www_form(@page.query.to_s).to_h.slice(*UTM_KEYS)
      .transform_values { |value| clip(value.squish.presence) }.compact
  rescue ArgumentError
    @utm = {}
  end

  def parse(raw)
    return if raw.blank?

    uri = URI.parse(raw.to_s)
    uri if %w[http https].include?(uri.scheme) && uri.host.present?
  rescue URI::InvalidURIError
    nil
  end

  def origin_of(uri)
    [ uri.scheme, "://", uri.host, (":#{uri.port}" if uri.port && uri.default_port != uri.port) ].compact.join
  end

  def clip(value)
    value&.truncate(MAX_LENGTH)
  end
end
