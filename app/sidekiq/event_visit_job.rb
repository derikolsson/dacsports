class EventVisitJob
  include Sidekiq::Job

  def perform(session_id, event_id, event_status, started_at, seen_at)
    # Use composite key to find or create EventVisit
    # This ensures one visit per session per event/status
    visit = EventVisit.find_or_initialize_by(
      session_id: session_id,
      event_id: event_id,
      event_status: event_status
    )

    # Set started_at only on first creation
    visit.started_at ||= started_at

    # Update last_seen_at (only if newer)
    visit.last_seen_at = seen_at unless visit.last_seen_at.present? && visit.last_seen_at > seen_at

    visit.save!
  end
end
