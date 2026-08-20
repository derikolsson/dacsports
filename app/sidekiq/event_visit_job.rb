class EventVisitJob
  include Sidekiq::Job

  def perform(session_id, event_id, event_status, started_at, seen_at, source = nil, referrer_origin = nil)
    source = source.presence || EventVisit::DEFAULT_SOURCE

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
    visit.started_at ||= started_at

    # Update last_seen_at (only if newer)
    visit.last_seen_at = seen_at unless visit.last_seen_at.present? && visit.last_seen_at > seen_at

    visit.save!
  end
end
