require 'rails_helper'

RSpec.describe ReportsQuery do
  let(:event) { create(:event, :replay_available, start_at: 2.days.ago) }
  let(:range) { { start_date: 10.days.ago.to_date, end_date: Date.current } }

  let!(:on_site_visit) do
    create(:event_visit, :vod, event: event,
                               session: create(:session, device_type: "desktop"),
                               started_at: 1.day.ago)
  end

  let!(:partner_visit) do
    create(:event_visit, :vod, :embedded, event: event,
                                          session: create(:session, device_type: "smartphone"),
                                          started_at: 1.day.ago)
  end

  # Embed visits share this table. Without scoping, every figure that predates the embed
  # work would silently start absorbing partner traffic — along with the unique-count
  # inflation that comes from third-party cookie blocking in the frame.
  describe 'default scope' do
    subject(:report) { described_class.new(**range) }

    it 'counts only on-site traffic' do
      expect(report.summary_stats[:vod]).to eq(users: 1, views: 1)
    end

    it 'excludes partner devices from the breakdown' do
      expect(report.device_breakdown.keys).to eq([ "Desktop" ])
    end

    it 'reports counts alongside percentages' do
      expect(report.device_breakdown["Desktop"]).to eq(live: 0, vod: 100.0, live_count: 0, vod_count: 1)
    end

    it 'excludes partner visits from the per-event breakdown' do
      row = report.per_event_stats.find { |r| r["id"] == event.id }
      expect(row["vod_viewers"]).to eq(1)
    end
  end

  describe 'scoped to all partners as a group' do
    subject(:report) { described_class.new(**range, source: described_class::ALL_PARTNERS) }

    let!(:second_partner) do
      create(:event_visit, :vod, event: event,
                                 session: create(:session, device_type: "tablet"),
                                 source: "embed:https://eastfield.example.edu",
                                 referrer_origin: "https://eastfield.example.edu",
                                 started_at: 1.day.ago)
    end

    it 'combines every partner and excludes on-site traffic' do
      expect(report.summary_stats[:vod]).to eq(users: 2, views: 2)
    end

    it 'excludes on-site devices from the breakdown' do
      expect(report.device_breakdown.keys).to match_array([ "Phone", "Tablet" ])
    end

    it 'compares partner sites, biggest first' do
      create(:event_visit, :live, event: event, source: "embed:https://eastfield.example.edu",
                                  referrer_origin: "https://eastfield.example.edu", started_at: 1.day.ago)

      rows = report.per_partner_stats
      expect(rows.map { |r| r[:label] }).to eq([ "https://eastfield.example.edu", "https://northlake.example.edu" ])
      expect(rows.first).to include(live_views: 1, vod_views: 1, share: 66.7)
    end

    it 'combines partners in the per-event breakdown' do
      row = report.per_event_stats.find { |r| r["id"] == event.id }
      expect(row["vod_viewers"]).to eq(2)
    end
  end

  # A partner page can feature a game long after it was played. Those views used to be
  # dropped by a 30-day cap, so a partner's report read zero while the rows existed.
  describe 'replay views long after the event' do
    subject(:report) { described_class.new(**range, source: "embed:https://northlake.example.edu") }

    let(:range) { { start_date: 120.days.ago.to_date, end_date: Date.current } }
    let(:old_event) { create(:event, :replay_available, start_at: 100.days.ago) }

    let!(:late_visit) do
      create(:event_visit, :vod, :embedded, event: old_event,
                                            session: create(:session, device_type: "tablet"),
                                            started_at: 1.day.ago)
    end

    it 'counts them in the summary, and keeps the 30-day figure separate' do
      expect(report.summary_stats[:vod]).to eq(users: 2, views: 2)
      expect(report.summary_stats[:vod_30d]).to eq(users: 1, views: 1)
    end

    it 'includes their devices in the breakdown' do
      expect(report.device_breakdown.keys).to match_array([ "Phone", "Tablet" ])
    end

    it 'counts them per event' do
      row = report.per_event_stats.find { |r| r["id"] == old_event.id }
      expect(row["vod_views"]).to eq(1)
    end
  end

  describe '.partner_sources' do
    it 'lists partner properties with traffic, labelled by origin' do
      expect(described_class.partner_sources)
        .to eq([ [ "https://northlake.example.edu", "embed:https://northlake.example.edu" ] ])
    end

    it 'does not list the on-site source' do
      expect(described_class.partner_sources.map(&:last)).not_to include(described_class::ON_SITE)
    end
  end

  describe 'scoped to a partner property' do
    subject(:report) { described_class.new(**range, source: "embed:https://northlake.example.edu") }

    it 'counts only that partner’s traffic' do
      expect(report.summary_stats[:vod]).to eq(users: 1, views: 1)
    end

    it 'reports that partner’s devices' do
      expect(report.device_breakdown.keys).to eq([ "Phone" ])
    end
  end

  # "Last 30 days" means viewing in the last 30 days, for events of any date. It used to
  # mean events that aired then, which hid this month's replays of older games.
  describe 'date range' do
    let(:old_event) { create(:event, :replay_available, start_at: 100.days.ago) }

    let!(:recent_replay) do
      create(:event_visit, :vod, event: old_event, started_at: 1.day.ago)
    end

    let!(:replay_before_range) do
      create(:event_visit, :vod, event: event, started_at: 20.days.ago)
    end

    subject(:report) { described_class.new(**range) }

    it 'counts viewing in the period, whenever the event aired' do
      expect(report.summary_stats[:vod]).to eq(users: 2, views: 2)
    end

    it 'lists only events viewed in the period, with counts that add up to the summary' do
      rows = report.per_event_stats

      expect(rows.map { |r| r["id"] }).to contain_exactly(event.id, old_event.id)
      expect(rows.sum { |r| r["vod_views"] }).to eq(report.summary_stats[:vod][:views])
    end

    it 'leaves out viewing before the period' do
      row = report.per_event_stats.find { |r| r["id"] == event.id }
      expect(row["vod_views"]).to eq(1)
    end

    it 'leaves out events with no viewing in the period' do
      quiet = create(:event, :replay_available, start_at: 3.days.ago)
      expect(report.per_event_stats.map { |r| r["id"] }).not_to include(quiet.id)
    end

    it 'uses the server time when the browser sent none' do
      recent_replay.update_columns(started_at: nil, created_at: 100.days.ago)

      expect(report.summary_stats[:vod][:views]).to eq(1)
    end
  end

  describe '#previous_period' do
    subject(:previous) { described_class.new(**range, source: described_class::ALL_PARTNERS).previous_period }

    it 'covers the same number of days immediately before' do
      expect(previous.start_date.to_date).to eq(21.days.ago.to_date)
      expect(previous.end_date.to_date).to eq(11.days.ago.to_date)
    end

    it 'keeps the audience' do
      expect(previous.source).to eq(described_class::ALL_PARTNERS)
    end

    it 'is nil for an all-time report' do
      report = described_class.new(start_date: described_class::ALL_TIME_START, end_date: Date.current)
      expect(report.previous_period).to be_nil
    end
  end

  describe 'peak live viewers' do
    subject(:report) { described_class.new(**range) }

    let(:live_event) { create(:event, start_at: 2.days.ago) }

    def watch(from, to)
      create(:event_visit, :live, event: live_event, started_at: from, last_seen_at: to)
    end

    it 'counts the most viewers watching at the same moment' do
      base = 2.days.ago
      watch(base, base + 60.minutes)
      watch(base + 10.minutes, base + 30.minutes)
      watch(base + 20.minutes, base + 40.minutes)
      watch(base + 50.minutes, base + 70.minutes)

      row = report.per_event_stats.find { |r| r["id"] == live_event.id }
      expect(row["live_peak"]).to eq(3)
    end

    it 'counts a viewer seen by a single poll' do
      at = 2.days.ago
      watch(at, at)

      row = report.per_event_stats.find { |r| r["id"] == live_event.id }
      expect(row["live_peak"]).to eq(1)
    end

    it 'is zero for events watched only as replays' do
      row = report.per_event_stats.find { |r| r["id"] == event.id }
      expect(row["live_peak"]).to eq(0)
    end
  end

  describe 'narrowed to a sport or team' do
    let(:team) { create(:team) }
    let(:soccer) { create(:event, :replay_available, sport: "Women's Soccer", start_at: 3.days.ago) }

    before do
      soccer.event_teams.create!(team: team)
      create(:event_visit, :vod, event: soccer, started_at: 1.day.ago)
    end

    it 'counts only that sport' do
      report = described_class.new(**range, sport: "Women's Soccer")

      expect(report.summary_stats[:vod][:views]).to eq(1)
      expect(report.per_event_stats.map { |r| r["id"] }).to eq([ soccer.id ])
    end

    it 'counts only that team' do
      report = described_class.new(**range, team_id: team.id)

      expect(report.summary_stats[:vod][:views]).to eq(1)
      expect(report.per_event_stats.map { |r| r["id"] }).to eq([ soccer.id ])
    end

    it 'carries the narrowing into the previous period' do
      previous = described_class.new(**range, sport: "Women's Soccer", team_id: team.id).previous_period
      expect([ previous.sport, previous.team_id ]).to eq([ "Women's Soccer", team.id ])
    end
  end

  describe 'Mux Data watch time and countries' do
    subject(:report) { described_class.new(**range) }

    def stat(**attrs)
      MuxDailyStat.create!(day: 1.day.ago.to_date, video_id: event.slug, event_id: event.id, audience: "dsn",
                           stream_type: "vod", views: 1, unique_viewers: 1, watch_time_ms: 0, **attrs)
    end

    before do
      stat(views: 3, watch_time_ms: 2 * 3_600_000)
      stat(stream_type: "live", views: 1, watch_time_ms: 3_600_000)
      stat(audience: "embed:https://northlake.example.edu", watch_time_ms: 5 * 3_600_000)
      stat(audience: "unknown", video_id: "PLAYBACKID", event_id: nil, watch_time_ms: 7 * 3_600_000)
      stat(day: 20.days.ago.to_date, video_id: "old", watch_time_ms: 11 * 3_600_000)
    end

    it "totals the audience's watch time in the period, split live and VOD" do
      expect(report.summary_stats[:watch]).to include(hours: 3.0, live_hours: 1.0, vod_hours: 2.0, per_view_minutes: 45.0)
    end

    it 'says when audience tagging began' do
      expect(report.summary_stats[:watch][:since]).to eq(20.days.ago.to_date)
    end

    it 'totals it per event' do
      row = report.per_event_stats.find { |r| r["id"] == event.id }
      expect(row["watch_minutes"]).to eq(180.0)
    end

    it 'combines partner audiences for all partners' do
      expect(described_class.new(**range, source: "partners").summary_stats[:watch][:hours]).to eq(5.0)
    end

    it 'narrows to the selected sport' do
      expect(described_class.new(**range, sport: "Baseball").summary_stats[:watch][:hours]).to eq(0)
    end

    it 'ranks countries by views for the audience' do
      [ [ "US", 5 ], [ "MX", 2 ] ].each do |code, views|
        MuxDailyCountry.create!(day: 1.day.ago.to_date, audience: "dsn", country_code: code, views: views, watch_time_ms: 60_000)
      end
      MuxDailyCountry.create!(day: 1.day.ago.to_date, audience: "embed:https://northlake.example.edu", country_code: "CA", views: 9, watch_time_ms: 0)

      expect(report.top_countries.map { |row| row.values_at(:country, :views) }).to eq([ [ "US", 5 ], [ "MX", 2 ] ])
    end

    it 'has no countries when narrowed to a sport, since they are not kept per event' do
      expect(described_class.new(**range, sport: "Baseball").top_countries).to be_nil
    end
  end

  describe '#daily_series' do
    subject(:series) { described_class.new(start_date: Date.new(2026, 3, 1), end_date: Date.new(2026, 3, 3)).daily_series }

    let(:march_event) { create(:event, :replay_available, start_at: Time.zone.local(2026, 2, 1)) }

    it 'buckets by the local day, not the UTC one' do
      # 11:30pm in Chicago on March 1 is already March 2 in UTC.
      create(:event_visit, :vod, event: march_event, started_at: Time.zone.local(2026, 3, 1, 23, 30))

      expect(series[:dates]).to eq([ Date.new(2026, 3, 1), Date.new(2026, 3, 2), Date.new(2026, 3, 3) ])
      expect(series[:vod]).to eq([ 1, 0, 0 ])
    end

    it 'counts each viewer once per day' do
      session = create(:session)
      create(:event_visit, :live, event: march_event, session: session, started_at: Time.zone.local(2026, 3, 2, 12))
      other = create(:session, visitor_id: session.visitor_id)
      create(:event_visit, :live, event: march_event, session: other, started_at: Time.zone.local(2026, 3, 2, 18))

      expect(series[:live]).to eq([ 0, 1, 0 ])
    end

    it 'switches to weeks for long periods' do
      long = described_class.new(start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 6, 30)).daily_series
      expect(long[:interval]).to eq("week")
      expect(long[:dates].first).to eq(Date.new(2025, 12, 29))
    end
  end

  describe 'play rate' do
    subject(:report) { described_class.new(**range) }

    it 'is unknown before any play has been recorded' do
      expect(report.summary_stats[:plays]).to include(since: nil, pct: nil)
    end

    it 'counts views that played, leaving out visits from before tracking began' do
      on_site_visit.update_columns(created_at: 5.days.ago)
      create(:event_visit, :vod, event: event, started_at: 1.day.ago, first_played_at: 1.day.ago)
      create(:event_visit, :vod, event: event, started_at: 1.day.ago)

      expect(report.summary_stats[:plays]).to include(plays: 1, views: 2, pct: 50)

      row = report.per_event_stats.find { |r| r["id"] == event.id }
      expect([ row["plays"], row["play_tracked_views"] ]).to eq([ 1, 2 ])
    end
  end

  describe '#top_pages' do
    subject(:report) { described_class.new(**range, source: described_class::ALL_PARTNERS) }

    it 'ranks partner pages by views' do
      2.times do
        create(:event_visit, :vod, :embedded, event: event, started_at: 1.day.ago,
                                              page_url: "https://northlake.example.edu/live", page_title: "Live")
      end
      create(:event_visit, :vod, :embedded, event: event, started_at: 1.day.ago, page_url: "https://northlake.example.edu/")

      expect(report.top_pages).to eq([
        { url: "https://northlake.example.edu/live", title: "Live", views: 2 },
        { url: "https://northlake.example.edu/", title: nil, views: 1 }
      ])
    end
  end

  describe '#traffic_sources' do
    it 'groups on-site views by how the session arrived' do
      on_site_visit.session.update!(landing_path: "/", landing_referrer_host: "www.google.com")
      tagged = create(:session, landing_path: "/events/final", landing_referrer_host: "www.google.com",
                                utm_source: "newsletter", utm_campaign: "homecoming")
      create(:event_visit, :vod, event: event, session: tagged, started_at: 1.day.ago)

      expect(described_class.new(**range).traffic_sources).to contain_exactly(
        { source: "www.google.com", campaign: nil, views: 1 },
        { source: "newsletter", campaign: "homecoming", views: 1 }
      )
    end

    it 'groups partner views by how the viewer reached the partner page' do
      partner_visit.update!(page_url: "https://northlake.example.edu/live", host_referrer_origin: "https://www.facebook.com")

      expect(described_class.new(**range, source: described_class::ALL_PARTNERS).traffic_sources)
        .to eq([ { source: "https://www.facebook.com", campaign: nil, views: 1 } ])
    end

    it 'leaves out visits from before sources were recorded' do
      expect(described_class.new(**range).traffic_sources).to eq([])
    end
  end
end
