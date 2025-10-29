class EventVisitJob
  include Sidekiq::Job

  def perform(visit_id, session_id, event_id, event_status, started_at, seen_at)
    visit = EventVisit.find_or_initialize_by(id: visit_id)

    # Set attributes on initialization
    if visit.new_record?
      visit.session_id = session_id
      visit.event_id = event_id
      visit.event_status = event_status
      visit.started_at = started_at
    end

    visit.last_seen_at = seen_at unless visit.last_seen_at.present? && visit.last_seen_at > seen_at
    visit.save!
  end
end
