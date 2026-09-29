require 'rails_helper'

RSpec.describe MuxDataImport do
  let(:api) { instance_double(MuxRuby::MetricsApi) }
  let(:day) { Date.new(2026, 9, 28) }
  let(:event) { create(:event, slug: "north-lake-richland", start_at: day.in_time_zone.change(hour: 19)) }

  # Answers each breakdown call by its group_by and filters.
  def stub_breakdowns(responses)
    allow(api).to receive(:list_breakdown_values) do |_metric, opts|
      rows = responses.fetch([ opts[:group_by], opts[:filters] ], [])
      MuxRuby::ListBreakdownValuesResponse.new(data: rows.map { |row| MuxRuby::BreakdownValue.new(**row) }, total_row_count: rows.size)
    end
  end

  def import = described_class.new(api: api).import(day)

  before do
    stub_breakdowns(
      [ "video_id", [] ] => [ { field: event.slug }, { field: "PLAYBACKID" } ],
      [ "stream_type", [] ] => [ { field: "on-demand" }, { field: "live-standard-latency" }, { field: "live-low-latency" } ],
      [ "custom_1", [ "video_id:#{event.slug}", "stream_type:on-demand" ] ] => [
        { field: "dsn", views: 5, value: 4.0, total_watch_time: 60_000 },
        { field: "embed:https://northlake.example.edu", views: 2, value: 2.0, total_watch_time: nil }
      ],
      [ "custom_1", [ "video_id:#{event.slug}", "stream_type:live-standard-latency" ] ] => [ { field: "dsn", views: 3, value: 3.0, total_watch_time: 1_000 } ],
      [ "custom_1", [ "video_id:#{event.slug}", "stream_type:live-low-latency" ] ] => [ { field: "dsn", views: 1, value: 1.0, total_watch_time: 500 } ],
      [ "custom_1", [ "video_id:PLAYBACKID", "stream_type:on-demand" ] ] => [ { field: nil, views: 9, value: 8.0, total_watch_time: 90_000 } ],
      [ "country", [] ] => [ { field: "US" }, { field: "MX" } ],
      [ "custom_1", [ "country:US" ] ] => [ { field: "dsn", views: 8, value: 7.0, total_watch_time: 61_000 }, { field: nil, views: 9 } ],
      [ "custom_1", [ "country:MX" ] ] => [ { field: "embed:https://northlake.example.edu", views: 2, value: 2.0 } ]
    )
  end

  it 'records views, unique viewers and watch time per video, audience and stream type' do
    import

    expect(MuxDailyStat.where(video_id: event.slug, stream_type: "vod").pluck(:audience, :event_id, :views, :unique_viewers, :watch_time_ms))
      .to contain_exactly([ "dsn", event.id, 5, 4, 60_000 ], [ "embed:https://northlake.example.edu", event.id, 2, 2, 0 ])
  end

  it 'folds every Mux live type into one live row' do
    import

    expect(MuxDailyStat.find_by(video_id: event.slug, stream_type: "live")).to have_attributes(views: 4, unique_viewers: 4, watch_time_ms: 1_500)
  end

  it 'keeps untagged views under unknown, without an event when the ID matches none' do
    import

    expect(MuxDailyStat.find_by(video_id: "PLAYBACKID")).to have_attributes(audience: "unknown", event_id: nil, views: 9)
  end

  it 'records countries per audience, leaving out untagged views' do
    import

    expect(MuxDailyCountry.pluck(:audience, :country_code, :views))
      .to contain_exactly([ "dsn", "US", 8 ], [ "embed:https://northlake.example.edu", "MX", 2 ])
  end

  it 'replaces the day on rerun' do
    import
    MuxDailyStat.create!(day: day, video_id: "gone", audience: "dsn", stream_type: "vod")

    expect { import }.to change(MuxDailyStat, :count).from(5).to(4)
  end

  describe 'matching videos to events' do
    it 'follows renamed slugs' do
      event.update!(slug: "renamed")
      import

      expect(MuxDailyStat.where(video_id: "north-lake-richland").pluck(:event_id).uniq).to eq([ event.id ])
    end

    it 'matches replay playback IDs' do
      replay = create(:event, :replay_available, mux_replay_playback_id: "PLAYBACKID")
      import

      expect(MuxDailyStat.find_by(video_id: "PLAYBACKID").event_id).to eq(replay.id)
    end

    it 'matches a live playback ID only when one event on its channel aired that day' do
      channel = create(:channel, mux_live_playback_id: "PLAYBACKID")
      event.update!(channel: channel)
      import
      expect(MuxDailyStat.find_by(video_id: "PLAYBACKID").event_id).to eq(event.id)

      create(:event, channel: channel, start_at: day.in_time_zone.change(hour: 13))
      import
      expect(MuxDailyStat.find_by(video_id: "PLAYBACKID").event_id).to be_nil
    end
  end

  it 'waits as long as Mux asks when rate limited, then retries' do
    empty = MuxRuby::ListBreakdownValuesResponse.new(data: [], total_row_count: 0)
    limited = MuxRuby::TooManyRequestsError.new(code: 429, response_headers: { "retry-after" => "14" })
    calls = 0
    allow(api).to receive(:list_breakdown_values) { (calls += 1) == 1 ? raise(limited) : empty }
    importer = described_class.new(api: api)
    allow(importer).to receive(:sleep)

    importer.import(day)

    expect(importer).to have_received(:sleep).with(15)
    expect(calls).to be > 1
  end
end
