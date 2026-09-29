require 'rails_helper'

RSpec.describe DashboardQuery do
  let(:event) { create(:event, :live) }
  let(:visitor) { SecureRandom.uuid }

  before do
    # One person, two sessions on dacsports.net, plus one partner-site viewer.
    2.times { create(:event_visit, :live, event: event, session: create(:session, visitor_id: visitor, device_type: "desktop"), started_at: 1.hour.ago, last_seen_at: 1.minute.ago) }
    create(:event_visit, :live, :embedded, event: event, session: create(:session, device_type: "smartphone"), started_at: 1.hour.ago, last_seen_at: 1.minute.ago)
  end

  it 'counts everyone watching now, split by audience' do
    expect(described_class.new.active_viewers).to eq(total: 3, on_site: 2, partners: 1)
  end

  it 'lists what they are watching, per audience' do
    rows = described_class.new.active_viewers_by_event
    expect(rows.map { |r| [ r[:partner], r[:viewers] ] }).to eq([ [ false, 2 ], [ true, 1 ] ])
  end

  it 'counts the week as the report does: viewers are browsers, views are sessions' do
    week = described_class.new.week

    expect(week[:current][:total]).to eq(users: 1, views: 2)
    expect(week[:previous][:total]).to eq(users: 0, views: 0)
  end

  describe 'watch time' do
    def watched(days_ago, hours)
      MuxDailyStat.create!(day: days_ago.days.ago.to_date, video_id: event.slug, event_id: event.id, audience: "dsn",
                           stream_type: "live", views: 1, unique_viewers: 1, watch_time_ms: hours * 3_600_000)
    end

    it 'compares the week with the one before when Mux Data covers both' do
      watched(20, 1)
      watched(10, 2)
      watched(1, 3)
      week = described_class.new.week

      expect([ week[:current][:watch][:hours], week[:previous][:watch][:hours], week[:compare_watch] ]).to eq([ 3.0, 2.0, true ])
    end

    it 'does not compare when Mux Data starts inside the previous week' do
      watched(10, 2)

      expect(described_class.new.week[:compare_watch]).to be(false)
    end

    it 'adds watch time to the top events' do
      watched(1, 3)

      expect(described_class.new.top_events.first["watch_minutes"]).to eq(180.0)
    end
  end

  it 'gives partner sites a share of all views' do
    expect(described_class.new.partner_share).to eq(current: 33, previous: 0)
  end

  it 'scopes the device share to the audience' do
    expect(described_class.new.device_share).to eq([ [ "Desktop", 100 ] ])
    expect(described_class.new(source: ReportsQuery::ALL_PARTNERS).device_share).to eq([ [ "Phone", 100 ] ])
  end

  it 'ranks this week’s events by views' do
    quiet = create(:event, :replay_available, title: "Quiet")
    create(:event_visit, :vod, event: quiet, started_at: 1.day.ago)

    expect(described_class.new.top_events.map { |r| [ r["id"], r["views"] ] }).to eq([ [ event.id, 2 ], [ quiet.id, 1 ] ])
  end

  it 'ranks partner sites' do
    expect(described_class.new.top_partners.map { |r| r[:label] }).to eq([ "https://northlake.example.edu" ])
  end

  it 'lists visible events in the next 7 days, soonest first' do
    later = create(:event, start_at: 3.days.from_now)
    sooner = create(:event, start_at: 1.day.from_now)
    create(:event, start_at: 1.day.from_now, visible: false)
    create(:event, start_at: 10.days.from_now)

    expect(described_class.new.upcoming_events).to eq([ sooner, later ])
  end

  it 'reports today’s peak live audience' do
    event.update!(title: "Tonight")
    expect(described_class.new.peak_today).to eq(title: "Tonight", viewers: 2)
  end

  it 'falls back to dacsports.net for an unknown audience' do
    expect(described_class.new(source: "embed:https://anything.example").source).to eq(ReportsQuery::ON_SITE)
  end
end
