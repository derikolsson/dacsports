class SessionKeepaliveJob
  include Sidekiq::Job

  def perform(session_id, seen_at)
    session = Session.find_by(id: session_id)
    return if session.nil?

    # Only update if the new timestamp is more recent
    session.update(last_seen_at: seen_at) unless session.last_seen_at && session.last_seen_at > seen_at
  end
end
