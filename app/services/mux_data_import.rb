# Copies Mux Data's daily figures into mux_daily_stats and mux_daily_countries.
#
# Each Chicago day is rebuilt whole: its rows are deleted and reinserted in one
# transaction, so rerunning a day is always safe and a view Mux later drops disappears
# here too. Mux counts a view once it ends, so a day keeps changing until its last
# views close; the nightly job re-imports the last few days for that reason.
#
# Filters only ever name video IDs, stream types and countries. custom_1 values
# ("embed:https://…") contain colons, which Mux's "dimension:value" filter syntax
# can't be trusted with, so audiences are always a group_by.
class MuxDataImport
  # Every breakdown row carries views, total watch time and, as its value, unique viewers.
  METRIC = "unique_viewers".freeze
  PAGE_SIZE = 250
  # Mux allows a burst of 50 requests, then says how long to wait in Retry-After.
  # A 100-day backfill needs over a thousand, so it waits many times.
  RATE_LIMIT_RETRIES = 10

  def initialize(api: MuxRuby::MetricsApi.new)
    @api = api
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
      breakdown("custom_1", timeframe, filters: [ "video_id:#{video_id}", "stream_type:#{mux_type}" ]).map do |row|
        { day: day, video_id: video_id, event_id: event_ids[video_id], audience: row.field.presence || MuxDailyStat::UNKNOWN,
          stream_type: type, views: row.views.to_i, unique_viewers: row.value.to_i, watch_time_ms: row.total_watch_time.to_i }
      end
    end

    # Several Mux live types (standard, low latency…) fold into one "live" row.
    rows.group_by { |row| row.values_at(:video_id, :audience, :stream_type) }.map do |_key, group|
      group.first.merge(%i[views unique_viewers watch_time_ms].to_h { |key| [ key, group.sum { |row| row[key] } ] })
    end
  end

  # Countries per audience. Views with no audience tag are left out: they can't be
  # shown under any audience in the report.
  def day_countries(day, timeframe)
    countries = breakdown("country", timeframe).filter_map(&:field)

    countries.flat_map do |country|
      breakdown("custom_1", timeframe, filters: [ "country:#{country}" ]).filter_map do |row|
        next if row.field.blank?

        { day: day, audience: row.field, country_code: country, views: row.views.to_i, watch_time_ms: row.total_watch_time.to_i }
      end
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
