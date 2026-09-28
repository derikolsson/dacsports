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

  # The last 7 days (today included) for this audience, as the viewership report
  # counts them, with the 7 days before for comparison.
  def week
    report = week_report(source)
    { current: report.summary_stats, previous: report.previous_period.summary_stats }
  end

  # Partner sites' share of all viewing sessions over the last 7 days, and the week
  # before. Sessions can be added across audiences; unique viewers can't.
  def partner_share
    on_site = week_report(ReportsQuery::ON_SITE)
    partners = week_report(ReportsQuery::ALL_PARTNERS)

    {
      current: share(partners, on_site),
      previous: share(partners.previous_period, on_site.previous_period)
    }
  end

  def week_range
    { start_date: 6.days.ago.to_date, end_date: Date.current }
  end

  # This audience's most-watched events over the last 7 days, by viewing sessions.
  def top_events(limit: 5)
    week_report(source).per_event_stats
      .map { |row| row.merge("views" => row["live_views"] + row["vod_views"]) }
      .max_by(limit) { |row| row["views"] }
  end

  def top_partners(limit: 5)
    week_report(ReportsQuery::ALL_PARTNERS).per_partner_stats.first(limit)
  end

  def upcoming_events(limit: 5)
    Event.visible.where(start_at: Time.current..7.days.from_now).order(:start_at).limit(limit)
  end

  # Today's biggest live audience at a single moment, in this audience: { event:, viewers: }.
  def peak_today
    row = ReportsQuery.new(start_date: Date.current, end_date: Date.current, source: source)
      .per_event_stats.max_by { |r| r["live_peak"] }
    return unless row && row["live_peak"].positive?

    { title: row["title"], viewers: row["live_peak"] }
  end

  # Share of this audience's viewing sessions over the last 7 days by device type,
  # biggest first: [["Phone", 62.5], ...]
  def device_share
    week_report(source).device_breakdown.map do |device, stats|
      [ device, stats[:live_count] + stats[:vod_count] ]
    end.then do |counts|
      total = counts.sum(&:last)
      counts.map { |device, count| [ device, total.positive? ? (count * 100.0 / total).round : 0 ] }
            .sort_by { |_, pct| -pct }
    end
  end

  private

  def week_report(audience)
    ReportsQuery.new(**week_range, source: audience)
  end

  def share(partners_report, on_site_report)
    partners = partners_report.summary_stats[:total][:views]
    total = partners + on_site_report.summary_stats[:total][:views]
    total.positive? ? (partners * 100.0 / total).round : 0
  end

  def active_visits
    EventVisit.where("last_seen_at > ?", ACTIVE_WINDOW.ago)
  end
end
