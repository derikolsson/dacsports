require 'rails_helper'

RSpec.describe ReportsCsv do
  let(:event) { create(:event, :replay_available, title: "Spring Final", sport: "Women's Soccer", start_at: 3.days.ago) }
  let(:query) { ReportsQuery.new(start_date: Date.new(2026, 9, 1), end_date: Date.current, basis: basis) }
  let(:basis) { ReportsQuery::ACTIVITY }
  let(:csv) do
    described_class.new(query, audience: "dacsports.net",
                               summary: query.summary_stats, event_stats: query.per_event_stats)
  end
  let(:rows) { CSV.parse(csv.to_csv) }

  before { create(:event_visit, :vod, event: event, started_at: 1.day.ago, last_seen_at: 1.day.ago + 30.minutes) }

  it 'says what was counted before any numbers' do
    expect(rows[1..3]).to eq([
      [ "Period", "2026-09-01 to #{Date.current}" ],
      [ "Counting", "Viewing that happened in the period" ],
      [ "Audience", "dacsports.net" ]
    ])
  end

  it 'includes the summary and one row per event' do
    expect(rows).to include([ "VOD", "1", "1" ])
    expect(rows.last).to eq([ "Spring Final", event.start_at.in_time_zone("America/Chicago").strftime("%Y-%m-%d %H:%M"),
                              "Women's Soccer", "0", "0.5", "0", "0", "1", "1" ])
  end

  context 'counting by events aired' do
    let(:basis) { ReportsQuery::AIRED }

    it 'includes the days-after-air columns' do
      expect(rows).to include(a_collection_including("VOD - 30D viewers", "VOD - All views"))
    end
  end

  it 'names the file after the period, basis and audience' do
    expect(csv.filename).to eq("dsn-viewership-2026-09-01-to-#{Date.current}-activity-dacsports-net.csv")
  end
end
