# Signed player served to distribution partners in a cross-origin iframe.
#
# Two independent control layers:
#   - the Mux playback restriction controls which ORIGIN may play the video
#   - CSP frame-ancestors controls which PAGE may frame this route
#
# Both are anti-hotlinking, not DRM. A determined actor can spoof headers; the point
# is bandwidth control, not access control.
class EmbedsController < ApplicationController
  include EventLookup

  skip_forgery_protection only: :status

  # Rails appends verify_same_origin_request to block cross-origin <script> loads of JS
  # responses (JSON/JS hijacking defence). embed.js is loaded cross-origin by design —
  # that is the entire delivery mechanism — and it contains no user data to hijack.
  skip_after_action :verify_same_origin_request, only: :script

  layout "embed"

  before_action :allow_framing
  after_action :log_embed_request, only: :show

  # States where we hand out a signed token. Everything else renders a slate and signs
  # nothing — that is what makes a denial state real rather than cosmetic, since a
  # reload that re-signed would just re-issue a token to someone being cut off.
  PLAYABLE_STATUSES = %w[live replay_available].freeze

  # Parent-page values arrive from the wrapper and are attacker-controllable. They are
  # logged, never rendered.
  MAX_PARAM_LENGTH = 2048

  def show
    @event, retired_slug = find_event_by_slug(params[:slug])
    return render_missing unless @event

    if retired_slug
      redirect_to embed_path(@event.slug), status: :moved_permanently, allow_other_host: false
      return
    end

    # Deliberately does not honour ?preview=true. Preview is an internal affordance and
    # must not be reachable from a district page.
    return render_missing unless @event.visible?

    @source = embed_source
    @visitor_id = embed_visitor_id
    @stream_type = @event.live? ? "live" : "on-demand"
    @poll_ttl = poll_ttl
    @tokens, @playback_id = signed_playback

    render :show
  end

  def status
    event, = find_event_by_slug(params[:slug])
    return head :not_found unless event && event.visible?

    track_visit(event)

    render json: {
      status: event.status,
      force_reload_version: event.force_reload_count,
      ttl: poll_ttl
    }
  end

  # Served through the controller rather than as a static or Propshaft asset so it can
  # have both a stable URL districts paste once and a short TTL. public/ inherits a
  # one-year cache-control, and Propshaft fingerprints the filename.
  def script
    expires_in 5.minutes, public: true
    render plain: self.class.embed_script, content_type: "application/javascript"
  end

  SCRIPT_PATH = Rails.root.join("app/assets/embed/embed.js")

  def self.embed_script
    # Re-read every request in development so edits show up without a restart; read once
    # in production because this is served on every partner page load.
    return SCRIPT_PATH.read if Rails.env.development?

    @embed_script ||= SCRIPT_PATH.read
  end

  private

  def render_missing
    @source = embed_source
    @visitor_id = embed_visitor_id
    render :missing, status: :not_found
  end

  def signed_playback
    return [ nil, nil ] unless PLAYABLE_STATUSES.include?(@event.status)

    playback_id = @event.live? ? @event.mux_live_signed_playback_id
                              : @event.mux_replay_signed_playback_id
    return [ nil, nil ] if playback_id.blank?
    return [ nil, nil ] unless MuxTokenSigner.configured?

    signer = MuxTokenSigner.new(playback_restriction_id: embed_restriction_id)
    [ signer.tokens_for(playback_id, live: @event.live?), playback_id ]
  rescue MuxTokenSigner::MissingSigningKey => e
    Rails.logger.error("[embed] signing unavailable: #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
    [ nil, nil ]
  end

  def embed_restriction_id
    Rails.application.credentials.dig(:mux, :playback_restriction_id_embed)
  end

  # Frames must not inherit the site's X-Frame-Options: SAMEORIGIN, which would block
  # every district page. frame-ancestors then decides who may actually frame us; it
  # ships as 'none' so the route fails closed before anyone depends on it.
  def allow_framing
    response.headers.delete("X-Frame-Options")
    response.headers["Content-Security-Policy"] = "frame-ancestors #{frame_ancestors}"
  end

  def frame_ancestors
    configured = redis_get("embed_frame_ancestors").presence
    # Fails CLOSED. If Redis is unreachable we deny framing rather than guess at a
    # partner list — the wrong direction here silently opens the route to anyone.
    configured || "'none'"
  end

  def poll_ttl
    redis_get("event_status_ttl").to_i.clamp(5_000, 300_000)
  end

  # This route is loaded inside seven third-party pages. A Redis blip should degrade it,
  # not 500 it.
  def redis_get(key)
    Dacsports.redis.get(key)
  rescue Redis::BaseError, Errno::ECONNREFUSED => e
    Rails.logger.warn("[embed] redis unavailable for #{key}: #{e.message}")
    nil
  end

  def track_visit(event)
    return unless params[:session_id].present?
    return unless EventVisit::TRACKED_STATUSES.include?(visit_status(event))

    EventVisitJob.perform_async(
      params[:session_id],
      event.id,
      visit_status(event),
      params[:started_at],
      Time.now.utc.iso8601(6),
      embed_source,
      referrer_origin
    )
  end

  def visit_status(event)
    event.replay_available? ? "vod" : event.status
  end

  # Partner identifier. Derived from the request's own Referer rather than anything the
  # wrapper sends, so a hostile parent cannot attribute its traffic to someone else.
  def embed_source
    origin = referrer_origin
    return "embed" if origin.blank?

    "embed:#{origin}"
  end

  def referrer_origin
    raw = request.referer.presence || request.headers["Origin"].presence
    return nil if raw.blank?

    uri = URI.parse(raw)
    return nil if uri.host.blank?

    [ uri.scheme, "://", uri.host, (":#{uri.port}" if uri.port && uri.default_port != uri.port) ].compact.join
  rescue URI::InvalidURIError
    nil
  end

  # Visitor identity inside a third-party frame.
  #
  # The site's own visitor_id cookie is SameSite=Lax, which browsers do not send in a
  # cross-site iframe, so the embed keeps its own. Partitioned (CHIPS) because that is
  # the only form Chrome still accepts here, and Safari partitions regardless.
  #
  # Consequence worth knowing when reading reports: third-party storage is partitioned
  # by top-level site, so this identifies a viewer on ONE partner property across page
  # loads and repeat visits, but never stitches them across two properties or with
  # dacsports.net. Those are separate visitors by browser design. Count uniques per
  # property; do not sum them into a total.
  def embed_visitor_id
    existing = cookies[:embed_visitor_id].presence
    return existing if existing

    generated = SecureRandom.uuid
    cookies[:embed_visitor_id] = {
      value: generated,
      expires: 1.year.from_now,
      path: "/embed",
      same_site: :none,
      secure: request.ssl?,
      httponly: false,
      partitioned: true
    }
    generated
  end

  # The unblockable analytics floor: cannot be defeated by an ad blocker and cannot
  # break the page. Wrapper params are enrichment and may be absent or hostile.
  def log_embed_request
    Rails.logger.info({
      tag: "embed",
      slug: params[:slug],
      status: @event&.status,
      signed: @tokens.present?,
      referer: request.referer&.truncate(MAX_PARAM_LENGTH),
      sec_fetch_site: request.headers["Sec-Fetch-Site"],
      parent_src: params[:src]&.to_s&.truncate(MAX_PARAM_LENGTH),
      parent_title: params[:title]&.to_s&.truncate(MAX_PARAM_LENGTH),
      ua: request.user_agent&.truncate(MAX_PARAM_LENGTH),
      ip: request.remote_ip
    }.compact.to_json)
  end
end
