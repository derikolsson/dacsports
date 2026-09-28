# Figures for the staff dashboard: what's happening right now, plus recent totals.
#
# Uses the same definitions as the viewership report: viewers are unique browsers
# (sessions.visitor_id), views are viewing sessions. Viewer counts are per audience and
# never added across dacsports.net and partner sites, because a browser gets a separate
# id on each property and would be counted twice.
class DashboardQuery
  # A viewer counts as watching if a poll has seen them this recently.
  ACTIVE_WINDOW = 3.minutes

  AUDIENCES = [ ReportsQuery::ON_SITE, ReportsQuery::ALL_PARTNERS ].freeze

  attr_reader :source

  def initialize(source: ReportsQuery::ON_SITE)
    @source = AUDIENCES.include?(source) ? source : ReportsQuery::ON_SITE
  end

  def partners?
    source == ReportsQuery::ALL_PARTNERS
  end

  # Sessions watching right now, everywhere. Sessions (unlike viewers) can be added
  # across properties, so this is the one figure that covers every audience at once.
  def active_viewers
    on_site = active_visits.on_site.distinct.count(:session_id)
    partners = active_visits.embedded.distinct.count(:session_id)

    { total: on_site + partners, on_site: on_site, partners: partners }
  end

  # [{ event:, status:, partner:, viewers: }] for every audience, events loaded in one query.
  def active_viewers_by_event
    counts = active_visits
      .group(:event_id, :event_status, Arel.sql("event_visits.source <> #{EventVisit.connection.quote(EventVisit::DEFAULT_SOURCE)}"))
      .distinct
      .count(:session_id)
    events = Event.where(id: counts.keys.map(&:first)).index_by(&:id)

    counts.filter_map do |(event_id, status, partner), viewers|
      event = events[event_id]
      { event: event, status: status, partner: partner, viewers: viewers } if event
    end.sort_by { |row| -row[:viewers] }
  end

  def audience_counts
    last_24h = audience_visits.joins(:session).where("event_visits.started_at > ?", 24.hours.ago)

    {
      viewers_24h: last_24h.distinct.count("sessions.visitor_id"),
      views_24h: last_24h.distinct.count("event_visits.session_id"),
      views_all_time: audience_visits.distinct.count(:session_id)
    }
  end

  # Viewing sessions in this audience, by each session attribute.
  def browser_breakdown = session_breakdown(:browser_name).first(10)
  def os_breakdown = session_breakdown(:os_name).first(10)
  def device_breakdown = session_breakdown(:device_type)

  private

  def active_visits
    EventVisit.where("last_seen_at > ?", ACTIVE_WINDOW.ago)
  end

  def audience_visits
    partners? ? EventVisit.embedded : EventVisit.on_site
  end

  def session_breakdown(column)
    audience_visits.joins(:session)
                   .group("sessions.#{column}")
                   .distinct
                   .count("event_visits.session_id")
                   .sort_by { |_k, v| -v }
  end
end
