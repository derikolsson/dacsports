class ReportsQuery
  attr_reader :start_date, :end_date

  def initialize(start_date:, end_date:)
    @start_date = start_date.beginning_of_day
    @end_date = end_date.end_of_day
  end

  def summary_stats
    live_stats = EventVisit
      .joins(:session, :event)
      .where(events: { start_at: start_date..end_date })
      .where(event_status: "live")

    vod_stats = EventVisit
      .joins(:session, :event)
      .where(events: { start_at: start_date..end_date })
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
    raw_counts = EventVisit
      .joins(:session, :event)
      .where(events: { start_at: start_date..end_date })
      .where("event_visits.event_status = 'live' OR (event_visits.event_status = 'vod' AND event_visits.started_at <= events.start_at + INTERVAL '30 days')")
      .group("sessions.device_type", "event_visits.event_status")
      .distinct
      .count("event_visits.session_id")

    calculate_percentages(raw_counts, method(:normalize_device_type))
  end

  def os_breakdown
    raw_counts = EventVisit
      .joins(:session, :event)
      .where(events: { start_at: start_date..end_date })
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
        COUNT(DISTINCT CASE WHEN ev.event_status = 'live' THEN s.visitor_id END) AS live_unique_viewers,
        COUNT(DISTINCT CASE WHEN ev.event_status = 'live' THEN ev.session_id END) AS live_views,
        COUNT(DISTINCT CASE WHEN ev.event_status = 'vod' AND ev.started_at <= e.start_at + INTERVAL '1 day' THEN s.visitor_id END) AS vod_1d_viewers,
        COUNT(DISTINCT CASE WHEN ev.event_status = 'vod' AND ev.started_at <= e.start_at + INTERVAL '1 day' THEN ev.session_id END) AS vod_1d_views,
        COUNT(DISTINCT CASE WHEN ev.event_status = 'vod' AND ev.started_at <= e.start_at + INTERVAL '7 days' THEN s.visitor_id END) AS vod_7d_viewers,
        COUNT(DISTINCT CASE WHEN ev.event_status = 'vod' AND ev.started_at <= e.start_at + INTERVAL '7 days' THEN ev.session_id END) AS vod_7d_views,
        COUNT(DISTINCT CASE WHEN ev.event_status = 'vod' AND ev.started_at <= e.start_at + INTERVAL '30 days' THEN s.visitor_id END) AS vod_30d_viewers,
        COUNT(DISTINCT CASE WHEN ev.event_status = 'vod' AND ev.started_at <= e.start_at + INTERVAL '30 days' THEN ev.session_id END) AS vod_30d_views
      FROM events e
      LEFT JOIN event_visits ev ON ev.event_id = e.id
      LEFT JOIN sessions s ON s.id = ev.session_id
      WHERE e.start_at BETWEEN :start_date AND :end_date
      GROUP BY e.id, e.title, e.start_at
      ORDER BY e.start_at ASC
    SQL

    ActiveRecord::Base.connection.exec_query(
      ActiveRecord::Base.sanitize_sql([ sql, { start_date: start_date, end_date: end_date } ])
    ).to_a
  end

  private

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
