class ReportsQuery
  attr_reader :start_date, :end_date, :source, :basis, :sport, :team_id

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

  # What the date range selects:
  #
  #   "activity" viewing that happened in the range, whenever the event aired (default)
  #   "aired"    all viewing, ever, of events that aired in the range
  #
  # The range used to mean "aired" without saying so, and read as "activity" to
  # everyone — so last month's replays of older games silently went missing.
  ACTIVITY = "activity".freeze
  AIRED = "aired".freeze
  BASES = [ ACTIVITY, AIRED ].freeze

  # started_at comes from the browser and was once nullable; created_at is the
  # server's first sighting.
  VISIT_START = "COALESCE(%{table}.started_at, %{table}.created_at)".freeze

  # sport and team_id optionally narrow every figure to that sport's or team's events.
  def initialize(start_date:, end_date:, source: ON_SITE, basis: ACTIVITY, sport: nil, team_id: nil)
    @start_date = start_date.beginning_of_day
    @end_date = end_date.end_of_day
    @source = source.presence || ON_SITE
    @basis = BASES.include?(basis) ? basis : ACTIVITY
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
  EVENT_COLUMNS = {
    "live" => "Live",
    "vod_1d" => "VOD - 1D",
    "vod_7d" => "VOD - 7D",
    "vod_30d" => "VOD - 30D",
    "vod_all" => "VOD - All"
  }.freeze

  # Under "activity" every count is already limited to the period, so the days-after-air
  # windows would only be slices of it; they belong to the "aired" view.
  def event_columns
    activity? ? { "live" => "Live", "vod_all" => "VOD" } : EVENT_COLUMNS
  end

  # The "All Time" preset starts here; nothing before it can be compared against.
  ALL_TIME_START = Date.new(2020, 1, 1)

  # The same-length period immediately before this one, with the same audience and basis.
  # nil when this period already reaches back to the start of time.
  def previous_period
    return if start_date.to_date <= ALL_TIME_START

    days = (end_date.to_date - start_date.to_date).to_i + 1
    self.class.new(start_date: start_date.to_date - days, end_date: start_date.to_date - 1,
                   source: source, basis: basis, sport: sport, team_id: team_id)
  end

  def all_partners?
    source == ALL_PARTNERS
  end

  def activity?
    basis == ACTIVITY
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
      player: player_time,
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

  def per_event_stats
    sql = <<~SQL
      SELECT
        e.id,
        e.title,
        e.start_at,
        e.sport,
        COUNT(DISTINCT CASE WHEN ev.event_status = 'live' THEN s.visitor_id END) AS live_viewers,
        COUNT(DISTINCT CASE WHEN ev.event_status = 'live' THEN ev.session_id END) AS live_views,
        COUNT(DISTINCT CASE WHEN ev.event_status = 'vod' AND ev.started_at <= e.start_at + INTERVAL '1 day' THEN s.visitor_id END) AS vod_1d_viewers,
        COUNT(DISTINCT CASE WHEN ev.event_status = 'vod' AND ev.started_at <= e.start_at + INTERVAL '1 day' THEN ev.session_id END) AS vod_1d_views,
        COUNT(DISTINCT CASE WHEN ev.event_status = 'vod' AND ev.started_at <= e.start_at + INTERVAL '7 days' THEN s.visitor_id END) AS vod_7d_viewers,
        COUNT(DISTINCT CASE WHEN ev.event_status = 'vod' AND ev.started_at <= e.start_at + INTERVAL '7 days' THEN ev.session_id END) AS vod_7d_views,
        COUNT(DISTINCT CASE WHEN ev.event_status = 'vod' AND ev.started_at <= e.start_at + INTERVAL '30 days' THEN s.visitor_id END) AS vod_30d_viewers,
        COUNT(DISTINCT CASE WHEN ev.event_status = 'vod' AND ev.started_at <= e.start_at + INTERVAL '30 days' THEN ev.session_id END) AS vod_30d_views,
        COUNT(DISTINCT CASE WHEN ev.event_status = 'vod' THEN s.visitor_id END) AS vod_all_viewers,
        COUNT(DISTINCT CASE WHEN ev.event_status = 'vod' THEN ev.session_id END) AS vod_all_views,
        COALESCE(SUM(#{player_seconds('ev')}), 0) / 60.0 AS player_minutes,
        COUNT(ev.first_played_at) AS plays,
        COUNT(ev.id) FILTER (WHERE ev.created_at >= :play_since) AS play_tracked_views
      FROM events e
      LEFT JOIN event_visits ev ON ev.event_id = e.id AND #{source_predicate} AND #{visit_range_predicate}
      LEFT JOIN sessions s ON s.id = ev.session_id
      WHERE #{event_range_predicate}
      GROUP BY e.id, e.title, e.start_at, e.sport
      #{"HAVING COUNT(ev.id) > 0" if activity?}
      ORDER BY e.start_at ASC
    SQL

    rows = ActiveRecord::Base.connection.exec_query(
      ActiveRecord::Base.sanitize_sql([ sql, { start_date: start_date, end_date: end_date, source: source, on_site: ON_SITE, sport: sport, team_id: team_id,
                  play_since: self.class.play_tracking_since || NEVER } ])
    ).to_a

    peaks = peak_live_concurrency
    rows.each { |row| row["live_peak"] = peaks.fetch(row["id"], 0) }
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

  # Filters the LEFT JOIN rather than the WHERE clause, so events with no visits from
  # this audience still appear in the report instead of dropping out of it.
  # An estimate of attention: how long pages with the player stayed open, from first to
  # last poll. It can't tell playing from paused, and misses the final poll interval.
  def player_time
    seconds, visits = scoped_visits.pick(
      Arel.sql("COALESCE(SUM(#{player_seconds('event_visits')}), 0)"), Arel.sql("COUNT(*)")
    )
    minutes = seconds.to_f / 60

    { minutes: minutes.round, per_visit: visits.positive? ? (minutes / visits).round(1) : 0 }
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

  def player_seconds(table)
    "GREATEST(EXTRACT(EPOCH FROM (#{table}.last_seen_at - #{format(VISIT_START, table: table)})), 0)"
  end

  def source_predicate
    all_partners? ? "ev.source <> :on_site" : "ev.source = :source"
  end

  # Under "activity" the range limits which visits count, so it joins alongside the
  # source — rows then add up to the summary. Under "aired" it limits which events
  # appear, and every visit to them counts.
  def visit_range_predicate
    return "TRUE" unless activity?

    "#{format(VISIT_START, table: 'ev')} BETWEEN :start_date AND :end_date"
  end

  def event_range_predicate
    predicates = []
    predicates << "e.start_at BETWEEN :start_date AND :end_date" unless activity?
    predicates << "e.sport = :sport" if sport
    predicates << "e.id IN (SELECT event_id FROM event_teams WHERE team_id = :team_id)" if team_id
    predicates.any? ? predicates.join(" AND ") : "TRUE"
  end

  def scoped_visits
    base = EventVisit.joins(:session, :event)
    base =
      if activity?
        base.where("#{format(VISIT_START, table: 'event_visits')} BETWEEN ? AND ?", start_date, end_date)
      else
        base.where(events: { start_at: start_date..end_date })
      end

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
