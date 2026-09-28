class EventVisitJob
  include Sidekiq::Job

  def perform(session_id, event_id, event_status, started_at, seen_at, source = nil, referrer_origin = nil)
    source = source.presence || EventVisit::DEFAULT_SOURCE
    seen_at = Time.zone.parse(seen_at.to_s)

    # One visit per session per event/status per source. An embed view and an on-site
    # view from the same session are genuinely different visits, so source has to
    # participate in the key or they overwrite each other.
    visit = EventVisit.find_or_initialize_by(
      session_id: session_id,
      event_id: event_id,
      event_status: event_status,
      source: source
    )

    visit.referrer_origin ||= referrer_origin

    # Set started_at only on first creation
    visit.started_at ||= trusted_started_at(started_at, seen_at)

    # Update last_seen_at (only if newer)
    visit.last_seen_at = seen_at unless visit.last_seen_at.present? && visit.last_seen_at > seen_at

    visit.save!

    # Embedded players never hit the keepalive endpoint, so the poll is the only sign
    # the viewer is still there. Without this, a session inside an iframe expires after
    # ten minutes and the next page load mints a new one, inflating view counts.
    Session.where(id: session_id)
           .where("last_seen_at IS NULL OR last_seen_at < ?", seen_at)
           .update_all(last_seen_at: seen_at)
  end

  private

  # started_at comes from the browser's clock, which can be missing, unparseable or
  # skewed into the future. Reports filter on it, so never let it land after the
  # server's own timestamp.
  def trusted_started_at(started_at, seen_at)
    parsed = Time.zone.parse(started_at.to_s) if started_at.present?
    parsed.nil? || parsed > seen_at ? seen_at : parsed
  rescue ArgumentError
    seen_at
  end
end
