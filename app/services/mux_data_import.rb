# Copies Mux Data's daily figures into mux_daily_stats and mux_daily_countries.
#
# Each Chicago day is rebuilt whole: its rows are deleted and reinserted in one
# transaction, so rerunning a day is always safe and a view Mux later drops disappears
# here too. Mux counts a view once it ends, so a day keeps changing until its last
# views close; the nightly job re-imports the last few days for that reason.
#
# Filters name video IDs, stream types and countries. custom_1 values
# ("embed:https://…") contain colons, which Mux's "dimension:value" filter syntax
# can't be trusted with, so audiences are a group_by; the one exception excludes
# colon-free values only (see #audience_rows).
class MuxDataImport
  # Every breakdown row carries views, total watch time and, as its value, unique viewers.
  METRIC = "unique_viewers".freeze
  PAGE_SIZE = 250
  # Mux allows a burst of 50 requests, then says how long to wait in Retry-After.
  # A 100-day backfill needs over a thousand, so it waits many times.
  RATE_LIMIT_RETRIES = 10

  def initialize(api: self.class.metrics_api)
    @api = api
  end

  # mux_ruby 5.1 checks group_by against a list that predates page_url, which Mux's
  # API accepts. This client skips that check; the shared configuration keeps it.
  def self.metrics_api
    config = MuxRuby::Configuration.default.dup
    config.client_side_validation = false
    MuxRuby::MetricsApi.new(MuxRuby::ApiClient.new(config))
  end

  # days: a Date or a range of Dates (Chicago).
  def import(days)
    Array(days).each { |day| import_day(day) }
  end

  private

  attr_reader :api

  def import_day(day)
    timeframe = [ day.in_time_zone.beginning_of_day.to_i, (day + 1).in_time_zone.beginning_of_day.to_i ].map(&:to_s)
    stats = day_stats(day, timeframe)
    countries = day_countries(day, timeframe)

    ApplicationRecord.transaction do
      MuxDailyStat.where(day: day).delete_all
      MuxDailyCountry.where(day: day).delete_all
      MuxDailyStat.insert_all!(stats) if stats.any?
      MuxDailyCountry.insert_all!(countries) if countries.any?
    end
  end

  def day_stats(day, timeframe)
    video_ids = breakdown("video_id", timeframe).filter_map(&:field)
    stream_types = breakdown("stream_type", timeframe).filter_map { |row| [ row.field, report_stream_type(row.field) ] if report_stream_type(row.field) }
    event_ids = EventLookup.new(video_ids, day).event_ids

    rows = video_ids.product(stream_types).flat_map do |video_id, (mux_type, type)|
      audience_rows(timeframe, [ "video_id:#{video_id}", "stream_type:#{mux_type}" ]).map do |audience, row|
        { day: day, video_id: video_id, event_id: event_ids[video_id], audience: audience,
          stream_type: type, views: row.views.to_i, unique_viewers: row.value.to_i, watch_time_ms: row.total_watch_time.to_i }
      end
    end

    # Several Mux live types (standard, low latency…) fold into one "live" row.
    fold(rows, %i[video_id audience stream_type], %i[views unique_viewers watch_time_ms])
  end

  # Countries per audience. Views with no known audience are left out: they can't be
  # shown under any audience in the report.
  def day_countries(day, timeframe)
    countries = breakdown("country", timeframe).filter_map(&:field)

    rows = countries.flat_map do |country|
      audience_rows(timeframe, [ "country:#{country}" ]).filter_map do |audience, row|
        next if audience == MuxDailyStat::UNKNOWN

        { day: day, audience: audience, country_code: country, views: row.views.to_i, watch_time_ms: row.total_watch_time.to_i }
      end
    end

    fold(rows, %i[audience country_code], %i[views watch_time_ms])
  end

  # [[audience, breakdown row], ...] for the views matching filters. Views from before
  # players sent custom_1 are placed by the page they played on instead, excluding the
  # tagged values by filter. That's only safe for colon-free values, which is all
  # there were while untagged views were still arriving; otherwise they stay unknown.
  # Unique viewers are summed across pages, so they can run slightly high there.
  def audience_rows(timeframe, filters)
    tagged, untagged = breakdown("custom_1", timeframe, filters: filters).partition { |row| row.field.present? }
    rows = tagged.map { |row| [ row.field, row ] }
    return rows if untagged.empty?
    return rows + untagged.map { |row| [ MuxDailyStat::UNKNOWN, row ] } if tagged.any? { |row| row.field.include?(":") }

    excluded = tagged.map { |row| "!custom_1:#{row.field}" }
    rows + breakdown("page_url", timeframe, filters: filters + excluded).map { |row| [ UntaggedAudience.for(row.field), row ] }
  end

  # Sums rows that share the same key fields.
  def fold(rows, keys, sums)
    rows.group_by { |row| row.values_at(*keys) }.map do |_key, group|
      group.first.merge(sums.to_h { |key| [ key, group.sum { |row| row[key] } ] })
    end
  end

  # "live" or "vod" for a Mux stream_type ("on-demand", "live-standard-latency", …).
  def report_stream_type(mux_type)
    return "vod" if mux_type == "on-demand"

    "live" if mux_type.to_s.start_with?("live")
  end

  def breakdown(dimension, timeframe, filters: [])
    rows = []
    page = 1
    loop do
      response = request { api.list_breakdown_values(METRIC, group_by: dimension, timeframe: timeframe, filters: filters, limit: PAGE_SIZE, page: page) }
      rows.concat(response.data)
      break if response.data.size < PAGE_SIZE || rows.size >= response.total_row_count.to_i

      page += 1
    end
    rows
  end

  def request
    attempts = 0
    begin
      yield
    rescue MuxRuby::TooManyRequestsError => e
      raise if (attempts += 1) > RATE_LIMIT_RETRIES

      sleep(e.response_headers.to_h["retry-after"].to_i.clamp(1, 60) + 1)
      retry
    end
  end

  # Before players sent custom_1 (Sep 28, 2026), the page a view played on is the only
  # clue to its audience. Remove once that date leaves Mux's 100-day retention, early
  # January 2027; the rows already imported keep their audience.
  module UntaggedAudience
    # First path segments of our public pages that play video. We serve several
    # domains, so the path decides, not the host.
    SITE_PAGES = [ "", "schedule", "archive", "events", "teams" ].freeze

    # page_url → "dsn", "embed:<partner origin>", "embed" (partner unknown) or "unknown".
    def self.for(page_url)
      page = URI.parse(page_url.to_s)
      # Older replays' pasted embed code, which played on our own event pages.
      return EventVisit::DEFAULT_SOURCE if page.host == "player.mux.com"
      return MuxDailyStat::UNKNOWN if page.host.blank?

      section = page.path.to_s.split("/")[1].to_s
      return EventVisit::DEFAULT_SOURCE if SITE_PAGES.include?(section)
      return MuxDailyStat::UNKNOWN unless section == "embed"

      # The embed URL carries the partner page as src, whose origin is what
      # EmbedsController records. localhost and our internal preview are our own testing.
      partner = URI.parse(Rack::Utils.parse_query(page.query)["src"].to_s)
      return "embed" if partner.host.blank?
      return MuxDailyStat::UNKNOWN if partner.host == "localhost" || partner.path.to_s.start_with?("/internal")

      "embed:#{partner.scheme}://#{partner.host}#{":#{partner.port}" if partner.port != partner.default_port}"
    rescue URI::InvalidURIError
      MuxDailyStat::UNKNOWN
    end
  end

  # Which event a Mux video_id is. Tagged players send the event slug (possibly one
  # since renamed); older views carry a playback ID instead, found in the event's Mux
  # columns or, for older replays, inside its pasted embed code. A channel's live
  # playback ID only identifies an event when one event on that channel aired that day.
  class EventLookup
    def initialize(video_ids, day)
      @video_ids = video_ids
      @day = day
    end

    def event_ids
      return {} if @video_ids.empty?

      live_playback_ids.merge(embedded_playback_ids).merge(replay_playback_ids).merge(old_slugs).merge(slugs)
    end

    private

    def slugs
      Event.where(slug: @video_ids).pluck(:slug, :id).to_h
    end

    def old_slugs
      EventSlug.where(slug: @video_ids).pluck(:slug, :event_id).to_h
    end

    def replay_playback_ids
      %i[mux_replay_playback_id mux_replay_signed_playback_id].each_with_object({}) do |column, ids|
        ids.merge!(Event.where(column => @video_ids).pluck(column, :id).to_h)
      end
    end

    def embedded_playback_ids
      patterns = @video_ids.map { |id| "%#{Event.sanitize_sql_like(id)}%" }
      codes = Event.where("replay_embed_code LIKE ANY (ARRAY[?])", patterns).pluck(:replay_embed_code, :id)

      @video_ids.each_with_object({}) do |video_id, ids|
        match = codes.find { |code, _| code.include?(video_id) }
        ids[video_id] = match.last if match
      end
    end

    def live_playback_ids
      %i[mux_live_playback_id mux_live_signed_playback_id].each_with_object({}) do |column, ids|
        Channel.where(column => @video_ids).pluck(column, :id).each do |playback_id, channel_id|
          aired = Event.where(channel_id: channel_id, start_at: @day.in_time_zone.all_day).pluck(:id)
          ids[playback_id] = aired.first if aired.one?
        end
      end
    end
  end
end
