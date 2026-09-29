class ReportsQuery
  attr_reader :start_date, :end_date, :source, :sport, :team_id

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

  # The date range selects viewing that happened in it, for events of any date. It
  # once selected events that aired in it, which silently dropped this month's
  # replays of older games.

  # started_at comes from the browser and was once nullable; created_at is the
  # server's first sighting.
  VISIT_START = "COALESCE(%{table}.started_at, %{table}.created_at)".freeze

  # sport and team_id optionally narrow every figure to that sport's or team's events.
  def initialize(start_date:, end_date:, source: ON_SITE, sport: nil, team_id: nil)
    @start_date = start_date.beginning_of_day
    @end_date = end_date.end_of_day
    @source = source.presence || ON_SITE
    @sport = sport.presence
    @team_id = team_id.presence&.to_i
  end

  # When the first play was recorded, which is when play tracking started. Nothing
  # before it can tell a play from a page left open.
  def self.play_tracking_since
    EventVisit.minimum(:first_played_at)
  end

  # Stands in for "no play tracking yet" in SQL, so no visit qualifies.
  NEVER = Time.utc(9999, 1, 1)

  # Per-event column groups: each key has "<key>_viewers" and "<key>_views" in
  # per_event_stats rows.
  EVENT_COLUMNS = { "live" => "Live", "vod" => "VOD" }.freeze

  # The "All Time" preset starts here; nothing before it can be compared against.
  ALL_TIME_START = Date.new(2020, 1, 1)

  # The same-length period immediately before this one, with the same audience and filters.
  # nil when this period already reaches back to the start of time.
  def previous_period
    return if start_date.to_date <= ALL_TIME_START

    days = (end_date.to_date - start_date.to_date).to_i + 1
    self.class.new(start_date: start_date.to_date - days, end_date: start_date.to_date - 1,
                   source: source, sport: sport, team_id: team_id)
  end

  def all_partners?
    source == ALL_PARTNERS
  end

  # Partner properties that actually have traffic, for the report's picker.
  def self.partner_sources
    EventVisit.embedded.distinct.pluck(:source, :referrer_origin)
         .map { |src, origin| [ origin.presence || "Unattributed", src ] }
         .sort_by { |label, _| label }
  end

  def summary_stats
    live_stats = scoped_visits
      .where(event_status: "live")

    # Replay views are counted however long after the event they happen. A partner
    # page can feature a game months later, and capping at 30 days hid every one of
    # those views. The 30-day figure is kept alongside for comparison with older reports.
    vod_stats = scoped_visits
      .where(event_status: "vod")

    vod_30d_stats = vod_stats
      .where("event_visits.started_at <= events.start_at + INTERVAL '30 days'")

    {
      total: {
        users: scoped_visits.distinct.count("sessions.visitor_id"),
        views: scoped_visits.distinct.count("event_visits.session_id")
      },
      watch: watch_time,
      plays: play_rate,
      live: {
        users: live_stats.distinct.count("sessions.visitor_id"),
        views: live_stats.distinct.count("event_visits.session_id")
      },
      vod: {
        users: vod_stats.distinct.count("sessions.visitor_id"),
        views: vod_stats.distinct.count("event_visits.session_id")
      },
      vod_30d: {
        users: vod_30d_stats.distinct.count("sessions.visitor_id"),
        views: vod_30d_stats.distinct.count("event_visits.session_id")
      }
    }
  end

  def device_breakdown
    raw_counts = scoped_visits
      .group("sessions.device_type", "event_visits.event_status")
      .distinct
      .count("event_visits.session_id")

    calculate_percentages(raw_counts, method(:normalize_device_type))
  end

  def os_breakdown
    raw_counts = scoped_visits
      .group("sessions.os_name", "event_visits.event_status")
      .distinct
      .count("event_visits.session_id")

    calculate_percentages(raw_counts, method(:normalize_os_name))
  end

  # One row per event viewed in the period, whenever it aired.
  def per_event_stats
    sql = <<~SQL
      SELECT
        e.id,
        e.title,
        e.start_at,
        e.sport,
        COUNT(DISTINCT CASE WHEN ev.event_status = 'live' THEN s.visitor_id END) AS live_viewers,
        COUNT(DISTINCT CASE WHEN ev.event_status = 'live' THEN ev.session_id END) AS live_views,
        COUNT(DISTINCT CASE WHEN ev.event_status = 'vod' THEN s.visitor_id END) AS vod_viewers,
        COUNT(DISTINCT CASE WHEN ev.event_status = 'vod' THEN ev.session_id END) AS vod_views,
        COUNT(ev.first_played_at) AS plays,
        COUNT(ev.id) FILTER (WHERE ev.created_at >= :play_since) AS play_tracked_views
      FROM event_visits ev
      JOIN events e ON e.id = ev.event_id
      JOIN sessions s ON s.id = ev.session_id
      WHERE #{source_predicate}
        AND #{format(VISIT_START, table: 'ev')} BETWEEN :start_date AND :end_date
        #{"AND e.sport = :sport" if sport}
        #{"AND e.id IN (SELECT event_id FROM event_teams WHERE team_id = :team_id)" if team_id}
      GROUP BY e.id, e.title, e.start_at, e.sport
      ORDER BY e.start_at ASC
    SQL

    rows = ActiveRecord::Base.connection.exec_query(
      ActiveRecord::Base.sanitize_sql([ sql, { start_date: start_date, end_date: end_date, source: source, on_site: ON_SITE, sport: sport, team_id: team_id,
                  play_since: self.class.play_tracking_since || NEVER } ])
    ).to_a

    peaks = peak_live_concurrency
    watched = mux_stats.where.not(event_id: nil).group(:event_id).sum(:watch_time_ms)
    rows.each do |row|
      row["live_peak"] = peaks.fetch(row["id"], 0)
      row["watch_minutes"] = watched.fetch(row["id"], 0) / 60_000.0
    end
  end

  # The first day Mux views carry an audience. Nothing before it can be split by
  # audience, so watch time and countries start here.
  def self.mux_tagged_since
    MuxDailyStat.where.not(audience: MuxDailyStat::UNKNOWN).minimum(:day)
  end

  # Countries by Mux views, most first: [{ country:, views:, watch_minutes: }]. nil when
  # a sport or team is selected: Mux's country figures aren't kept per event.
  def top_countries(limit: 10)
    return if sport || team_id

    MuxDailyCountry.where(day: mux_days).where(mux_audience(MuxDailyCountry))
      .group(:country_code)
      .order(Arel.sql("SUM(views) DESC"))
      .limit(limit)
      .pluck(:country_code, Arel.sql("SUM(views)"), Arel.sql("SUM(watch_time_ms)"))
      .map { |code, views, ms| { country: code, views: views, watch_minutes: ms / 60_000.0 } }
  end

  # Unique viewers per day (per week for long periods), split live and VOD, bucketed by
  # when the viewing happened.
  #
  #   { interval: "day", dates: [Date, ...], live: [Integer, ...], vod: [Integer, ...] }
  #
  # Bucket boundaries are local midnights computed here and quoted by Active Record,
  # which stores timestamps in the server's zone (default_timezone = :local). Converting
  # in SQL would have to guess that zone.
  def daily_series
    interval = (end_date.to_date - start_date.to_date) > 120 ? "week" : "day"
    step = interval == "week" ? 7 : 1
    first = interval == "week" ? start_date.to_date.beginning_of_week : start_date.to_date
    dates = (first..end_date.to_date).step(step).to_a

    buckets = dates.map do |date|
      from = date.in_time_zone.beginning_of_day
      to = (date + step).in_time_zone.beginning_of_day
      "(#{connection.quote(date)}::date, #{connection.quote(from)}::timestamp, #{connection.quote(to)}::timestamp)"
    end
    start = format(VISIT_START, table: "event_visits")

    counts = scoped_visits
      .joins("JOIN (VALUES #{buckets.join(', ')}) AS buckets(day, from_at, to_at) " \
             "ON #{start} >= buckets.from_at AND #{start} < buckets.to_at")
      .group("buckets.day", "event_visits.event_status")
      .distinct
      .count("sessions.visitor_id")

    {
      interval: interval,
      dates: dates,
      live: dates.map { |date| counts[[ date, "live" ]] || 0 },
      vod: dates.map { |date| counts[[ date, "vod" ]] || 0 }
    }
  end

  # One row per partner property, biggest first, with its share of all partner views.
  # Only meaningful for the "all partners" audience; each property is its own row
  # because a viewer can't be recognised from one property to the next.
  def per_partner_stats
    rows = scoped_visits
      .group("event_visits.source")
      .order(Arel.sql("COUNT(DISTINCT event_visits.session_id) DESC"))
      .pluck(
        "event_visits.source",
        Arel.sql("MAX(event_visits.referrer_origin)"),
        Arel.sql("COUNT(DISTINCT CASE WHEN event_visits.event_status = 'live' THEN sessions.visitor_id END)"),
        Arel.sql("COUNT(DISTINCT CASE WHEN event_visits.event_status = 'live' THEN event_visits.session_id END)"),
        Arel.sql("COUNT(DISTINCT CASE WHEN event_visits.event_status = 'vod' THEN sessions.visitor_id END)"),
        Arel.sql("COUNT(DISTINCT CASE WHEN event_visits.event_status = 'vod' THEN event_visits.session_id END)"),
        Arel.sql("COUNT(DISTINCT event_visits.session_id)")
      )

    total_views = rows.sum(&:last)
    rows.map do |src, origin, live_users, live_views, vod_users, vod_views, views|
      {
        source: src, label: origin.presence || "Unattributed",
        live_users: live_users, live_views: live_views, vod_users: vod_users, vod_views: vod_views,
        share: total_views.positive? ? (views * 100.0 / total_views).round(1) : 0
      }
    end
  end

  # Partner pages that embed views happened on, most viewed first:
  # [{ url:, title:, views: }]. Visits from before pages were recorded are left out.
  def top_pages(limit: 10)
    scoped_visits
      .where.not(page_url: nil)
      .group("event_visits.page_url")
      .order(Arel.sql("COUNT(DISTINCT event_visits.session_id) DESC"))
      .limit(limit)
      .pluck("event_visits.page_url", Arel.sql("MAX(event_visits.page_title)"),
             Arel.sql("COUNT(DISTINCT event_visits.session_id)"))
      .map { |url, title, views| { url: url, title: title, views: views } }
  end

  # What sent viewers, most views first: [{ source:, campaign:, views: }]. A UTM source
  # wins over the referring site when both are known.
  #
  # On-site, that's how the session arrived; on partner sites, how the viewer reached
  # the partner page. Visits from before this was recorded are left out.
  def traffic_sources(limit: 10)
    on_site = source == ON_SITE
    referrer = on_site ? "sessions.landing_referrer_host" : "event_visits.host_referrer_origin"
    utm = on_site ? "sessions" : "event_visits"
    recorded = on_site ? "sessions.landing_path IS NOT NULL" : "event_visits.page_url IS NOT NULL"
    label = "COALESCE(#{utm}.utm_source, #{referrer}, '(direct or unknown)')"

    scoped_visits
      .where(recorded)
      .group(Arel.sql(label), "#{utm}.utm_campaign")
      .order(Arel.sql("COUNT(DISTINCT event_visits.session_id) DESC"))
      .limit(limit)
      .pluck(Arel.sql(label), "#{utm}.utm_campaign", Arel.sql("COUNT(DISTINCT event_visits.session_id)"))
      .map { |name, campaign, views| { source: name, campaign: campaign, views: views } }
  end

  # The most live viewers watching an event at the same moment, keyed by event id.
  #
  # Each visit is open from its start to the last poll that saw it, so walking those
  # edges in time order and keeping a running total gives the peak. Precision is the
  # poll interval. At equal timestamps arrivals count first; otherwise a viewer seen by
  # only one poll (start == last seen) would never count as watching at all.
  def peak_live_concurrency
    visits = scoped_visits.where(event_status: "live")
    start = format(VISIT_START, table: "event_visits")

    sql = <<~SQL
      WITH edges AS (
        #{visits.select("event_visits.event_id, #{start} AS at, 1 AS delta").to_sql}
        UNION ALL
        #{visits.select("event_visits.event_id, COALESCE(event_visits.last_seen_at, #{start}) AS at, -1 AS delta").to_sql}
      ),
      running AS (
        SELECT event_id,
               SUM(delta) OVER (PARTITION BY event_id ORDER BY at, delta DESC ROWS UNBOUNDED PRECEDING) AS watching
        FROM edges
      )
      SELECT event_id, MAX(watching) AS peak FROM running GROUP BY event_id
    SQL

    ActiveRecord::Base.connection.select_rows(sql).to_h { |id, peak| [ id, peak.to_i ] }
  end

  private

  # How long the video actually played, from Mux Data, in hours: total, live and VOD.
  def watch_time
    ms = mux_stats.group(:stream_type).sum(:watch_time_ms)
    views = mux_stats.sum(:views)
    total = ms.values.sum

    {
      hours: total / 3_600_000.0,
      live_hours: ms.fetch("live", 0) / 3_600_000.0,
      vod_hours: ms.fetch("vod", 0) / 3_600_000.0,
      per_view_minutes: views.positive? ? (total / 60_000.0 / views).round(1) : 0,
      since: self.class.mux_tagged_since
    }
  end

  def connection = ActiveRecord::Base.connection

  # Of the views since play tracking began, how many pressed play (or autoplayed).
  # Earlier visits can't say, so they're left out rather than counted as not playing.
  def play_rate
    since = self.class.play_tracking_since
    return { since: nil, plays: 0, views: 0, pct: nil } unless since

    tracked = scoped_visits.where("event_visits.created_at >= ?", since)
    plays = tracked.where.not(first_played_at: nil).count
    views = tracked.count
    { since: since.to_date, plays: plays, views: views, pct: views.positive? ? (plays * 100.0 / views).round : nil }
  end

  def mux_days = start_date.to_date..end_date.to_date

  def mux_audience(model)
    all_partners? ? model.arel_table[:audience].matches("embed:%") : { audience: source }
  end

  def mux_stats
    stats = MuxDailyStat.where(day: mux_days).where(mux_audience(MuxDailyStat))
    stats = stats.where(event_id: Event.where(sport: sport).select(:id)) if sport
    stats = stats.where(event_id: EventTeam.where(team_id: team_id).select(:event_id)) if team_id
    stats
  end

  def source_predicate
    all_partners? ? "ev.source <> :on_site" : "ev.source = :source"
  end

  def scoped_visits
    base = EventVisit.joins(:session, :event)
      .where("#{format(VISIT_START, table: 'event_visits')} BETWEEN ? AND ?", start_date, end_date)

    base = base.where(events: { sport: sport }) if sport
    base = base.where(event_id: EventTeam.where(team_id: team_id).select(:event_id)) if team_id

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
        vod: totals["vod"].positive? ? (counts["vod"].to_f / totals["vod"] * 100).round(1) : 0,
        live_count: counts["live"],
        vod_count: counts["vod"]
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
