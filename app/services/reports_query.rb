class ReportsQuery
  attr_reader :start_date, :end_date, :source

  # Audience the figures cover:
  #
  #   "dsn"            DAC Sports Network's own site (the default, and what every
  #                    pre-existing report meant before embeds shared this table)
  #   "partners"       every partner property combined
  #   "embed:https://…" one specific partner property
  #
  # Defaulting to on-site matters: without it, existing numbers would silently absorb
  # partner traffic.
  ON_SITE = EventVisit::DEFAULT_SOURCE
  ALL_PARTNERS = "partners".freeze

  def initialize(start_date:, end_date:, source: ON_SITE)
    @start_date = start_date.beginning_of_day
    @end_date = end_date.end_of_day
    @source = source.presence || ON_SITE
  end

  def all_partners?
    source == ALL_PARTNERS
  end

  # Partner properties that actually have traffic, for the report's picker.
  def self.partner_sources(start_date: nil, end_date: nil)
    scope = EventVisit.embedded
    if start_date && end_date
      scope = scope.joins(:event).where(events: { start_at: start_date.beginning_of_day..end_date.end_of_day })
    end
    scope.distinct.pluck(:source, :referrer_origin)
         .map { |src, origin| [ origin.presence || "Unattributed", src ] }
         .sort_by { |label, _| label }
  end

  def summary_stats
    live_stats = scoped_visits
      .where(event_status: "live")

    vod_stats = scoped_visits
      .where(event_status: "vod")
      .where("event_visits.started_at <= events.start_at + INTERVAL '30 days'")

    {
      live: {
        users: live_stats.distinct.count("sessions.visitor_id"),
        views: live_stats.distinct.count("event_visits.session_id")
      },
      vod: {
        users: vod_stats.distinct.count("sessions.visitor_id"),
        views: vod_stats.distinct.count("event_visits.session_id")
      }
    }
  end

  def device_breakdown
    raw_counts = scoped_visits
      .where("event_visits.event_status = 'live' OR (event_visits.event_status = 'vod' AND event_visits.started_at <= events.start_at + INTERVAL '30 days')")
      .group("sessions.device_type", "event_visits.event_status")
      .distinct
      .count("event_visits.session_id")

    calculate_percentages(raw_counts, method(:normalize_device_type))
  end

  def os_breakdown
    raw_counts = scoped_visits
      .where("event_visits.event_status = 'live' OR (event_visits.event_status = 'vod' AND event_visits.started_at <= events.start_at + INTERVAL '30 days')")
      .group("sessions.os_name", "event_visits.event_status")
      .distinct
      .count("event_visits.session_id")

    calculate_percentages(raw_counts, method(:normalize_os_name))
  end

  def per_event_stats
    sql = <<~SQL
      SELECT
        e.id,
        e.title,
        e.start_at,
        e.sport,
        COUNT(DISTINCT CASE WHEN ev.event_status = 'live' THEN s.visitor_id END) AS live_unique_viewers,
        COUNT(DISTINCT CASE WHEN ev.event_status = 'live' THEN ev.session_id END) AS live_views,
        COUNT(DISTINCT CASE WHEN ev.event_status = 'vod' AND ev.started_at <= e.start_at + INTERVAL '1 day' THEN s.visitor_id END) AS vod_1d_viewers,
        COUNT(DISTINCT CASE WHEN ev.event_status = 'vod' AND ev.started_at <= e.start_at + INTERVAL '1 day' THEN ev.session_id END) AS vod_1d_views,
        COUNT(DISTINCT CASE WHEN ev.event_status = 'vod' AND ev.started_at <= e.start_at + INTERVAL '7 days' THEN s.visitor_id END) AS vod_7d_viewers,
        COUNT(DISTINCT CASE WHEN ev.event_status = 'vod' AND ev.started_at <= e.start_at + INTERVAL '7 days' THEN ev.session_id END) AS vod_7d_views,
        COUNT(DISTINCT CASE WHEN ev.event_status = 'vod' AND ev.started_at <= e.start_at + INTERVAL '30 days' THEN s.visitor_id END) AS vod_30d_viewers,
        COUNT(DISTINCT CASE WHEN ev.event_status = 'vod' AND ev.started_at <= e.start_at + INTERVAL '30 days' THEN ev.session_id END) AS vod_30d_views
      FROM events e
      LEFT JOIN event_visits ev ON ev.event_id = e.id AND #{source_predicate}
      LEFT JOIN sessions s ON s.id = ev.session_id
      WHERE e.start_at BETWEEN :start_date AND :end_date
      GROUP BY e.id, e.title, e.start_at, e.sport
      ORDER BY e.start_at ASC
    SQL

    ActiveRecord::Base.connection.exec_query(
      ActiveRecord::Base.sanitize_sql([ sql, { start_date: start_date, end_date: end_date, source: source, on_site: ON_SITE } ])
    ).to_a
  end

  private

  # Filters the LEFT JOIN rather than the WHERE clause, so events with no visits from
  # this audience still appear in the report instead of dropping out of it.
  def source_predicate
    all_partners? ? "ev.source <> :on_site" : "ev.source = :source"
  end

  def scoped_visits
    base = EventVisit
      .joins(:session, :event)
      .where(events: { start_at: start_date..end_date })

    all_partners? ? base.embedded : base.where(source: source)
  end

  def calculate_percentages(raw_counts, normalizer)
    totals = { "live" => 0, "vod" => 0 }
    grouped = {}

    raw_counts.each do |(raw_key, status), count|
      normalized = normalizer.call(raw_key)
      grouped[normalized] ||= { "live" => 0, "vod" => 0 }
      grouped[normalized][status] += count
      totals[status] += count
    end

    result = {}
    grouped.each do |key, counts|
      result[key] = {
        live: totals["live"].positive? ? (counts["live"].to_f / totals["live"] * 100).round(1) : 0,
        vod: totals["vod"].positive? ? (counts["vod"].to_f / totals["vod"] * 100).round(1) : 0
      }
    end

    sort_breakdown(result)
  end

  def sort_breakdown(breakdown)
    breakdown.sort_by { |_k, v| -(v[:live] + v[:vod]) }.to_h
  end

  def normalize_device_type(device_type)
    case device_type&.downcase
    when "smartphone" then "Phone"
    when "desktop" then "Desktop"
    when "tablet" then "Tablet"
    else "Other"
    end
  end

  def normalize_os_name(os_name)
    case os_name
    when "iOS", "iPadOS" then "iOS/iPadOS"
    when "Android" then "Android"
    when "Windows" then "Windows"
    when "Mac" then "macOS"
    else "Other"
    end
  end
end
