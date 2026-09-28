# Figures for the staff dashboard: what's happening right now, plus recent totals.
class DashboardQuery
  # A viewer counts as watching if a poll has seen them this recently.
  ACTIVE_WINDOW = 3.minutes

  def active_viewers
    active_visits.distinct.count(:session_id)
  end

  # [{ event:, status:, viewers: }], events loaded in one query.
  def active_viewers_by_event
    counts = active_visits.group(:event_id, :event_status).distinct.count(:session_id)
    events = Event.where(id: counts.keys.map(&:first)).index_by(&:id)

    counts.filter_map do |(event_id, status), viewers|
      event = events[event_id]
      { event: event, status: status, viewers: viewers } if event
    end
  end

  def view_counts
    {
      all_time: EventVisit.on_site.count,
      last_24h: EventVisit.on_site.where("started_at > ?", 24.hours.ago).count,
      last_7d: EventVisit.on_site.where("started_at > ?", 7.days.ago).count
    }
  end

  # Only sessions that have actually watched an event.
  def browser_breakdown = session_breakdown(:browser_name).first(10)
  def os_breakdown = session_breakdown(:os_name).first(10)
  def device_breakdown = session_breakdown(:device_type)

  private

  def active_visits
    EventVisit.on_site.where("last_seen_at > ?", ACTIVE_WINDOW.ago)
  end

  # Joins rather than WHERE IN, to avoid query size issues with large datasets.
  def session_breakdown(column)
    Session.joins(:event_visits).distinct.group(column).count.sort_by { |_k, v| -v }
  end
end
