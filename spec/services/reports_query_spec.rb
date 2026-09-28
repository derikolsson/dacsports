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
      expect(row["vod_30d_viewers"]).to eq(1)
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
      expect(row["vod_30d_viewers"]).to eq(2)
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

    it 'counts them per event under all-time, not under 30 days' do
      row = report.per_event_stats.find { |r| r["id"] == old_event.id }
      expect(row["vod_30d_views"]).to eq(0)
      expect(row["vod_all_views"]).to eq(1)
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

    # The source filter belongs in the LEFT JOIN's ON clause; in WHERE it would drop
    # every event that has no matching visit.
    it 'still lists aired events with no visits from that partner' do
      quiet = create(:event, :replay_available, start_at: 3.days.ago)
      other = described_class.new(**range, source: "embed:https://someone-else.org",
                                           basis: described_class::AIRED)

      expect(other.per_event_stats.map { |r| r["id"] }).to include(quiet.id)
    end
  end

  # "Last 30 days" has to mean viewing in the last 30 days. It used to mean events that
  # aired then, which hid this month's replays of older games.
  describe 'date basis' do
    let(:old_event) { create(:event, :replay_available, start_at: 100.days.ago) }

    let!(:recent_replay) do
      create(:event_visit, :vod, event: old_event, started_at: 1.day.ago)
    end

    let!(:replay_before_range) do
      create(:event_visit, :vod, event: event, started_at: 20.days.ago)
    end

    context 'by viewing activity (the default)' do
      subject(:report) { described_class.new(**range) }

      it 'counts viewing in the period, whenever the event aired' do
        expect(report.summary_stats[:vod]).to eq(users: 2, views: 2)
      end

      it 'lists only events viewed in the period, with counts that add up to the summary' do
        rows = report.per_event_stats

        expect(rows.map { |r| r["id"] }).to contain_exactly(event.id, old_event.id)
        expect(rows.sum { |r| r["vod_all_views"] }).to eq(report.summary_stats[:vod][:views])
      end

      it 'leaves out earlier viewing of events in the period' do
        row = report.per_event_stats.find { |r| r["id"] == event.id }
        expect(row["vod_all_views"]).to eq(1)
      end

      it 'uses the server time when the browser sent none' do
        recent_replay.update_columns(started_at: nil, created_at: 100.days.ago)

        expect(report.summary_stats[:vod][:views]).to eq(1)
      end
    end

    context 'by events aired' do
      subject(:report) { described_class.new(**range, basis: described_class::AIRED) }

      it 'counts all viewing of events that aired in the period' do
        row = report.per_event_stats.find { |r| r["id"] == event.id }
        expect(row["vod_all_views"]).to eq(2)
      end

      it 'leaves out events that aired earlier' do
        expect(report.per_event_stats.map { |r| r["id"] }).not_to include(old_event.id)
      end
    end

    it 'falls back to viewing activity for an unknown basis' do
      expect(described_class.new(**range, basis: "bogus")).to be_activity
    end
  end

  describe '#previous_period' do
    subject(:previous) { described_class.new(**range, source: described_class::ALL_PARTNERS, basis: described_class::AIRED).previous_period }

    it 'covers the same number of days immediately before' do
      expect(previous.start_date.to_date).to eq(21.days.ago.to_date)
      expect(previous.end_date.to_date).to eq(11.days.ago.to_date)
    end

    it 'keeps the audience and basis' do
      expect([ previous.source, previous.basis ]).to eq([ described_class::ALL_PARTNERS, described_class::AIRED ])
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

    it 'counts only that team, under either basis' do
      [ described_class::ACTIVITY, described_class::AIRED ].each do |basis|
        report = described_class.new(**range, team_id: team.id, basis: basis)

        expect(report.summary_stats[:vod][:views]).to eq(1)
        expect(report.per_event_stats.map { |r| r["id"] }).to eq([ soccer.id ])
      end
    end

    it 'carries the narrowing into the previous period' do
      previous = described_class.new(**range, sport: "Women's Soccer", team_id: team.id).previous_period
      expect([ previous.sport, previous.team_id ]).to eq([ "Women's Soccer", team.id ])
    end
  end

  describe 'time with the player open' do
    subject(:report) { described_class.new(**range) }

    before do
      on_site_visit.update_columns(started_at: 2.days.ago, last_seen_at: 2.days.ago + 30.minutes)
      create(:event_visit, :vod, event: event, started_at: 1.day.ago, last_seen_at: 1.day.ago + 10.minutes)
      # A skewed clock can put the start after the last poll; that counts as nothing.
      create(:event_visit, :vod, event: event, started_at: 1.day.ago, last_seen_at: 1.day.ago - 5.minutes)
    end

    it 'totals and averages it in the summary' do
      expect(report.summary_stats[:player]).to eq(minutes: 40, per_visit: 13.3)
    end

    it 'totals it per event' do
      row = report.per_event_stats.find { |r| r["id"] == event.id }
      expect(row["player_minutes"].to_f).to be_within(0.01).of(40)
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
end
