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

  it 'counts viewers as unique browsers and views as sessions, like the report' do
    expect(described_class.new.audience_counts).to eq(viewers_24h: 1, views_24h: 2, views_all_time: 2)
  end

  it 'scopes the device breakdown to the audience' do
    expect(described_class.new.device_breakdown).to eq([ [ "desktop", 2 ] ])
    expect(described_class.new(source: ReportsQuery::ALL_PARTNERS).device_breakdown).to eq([ [ "smartphone", 1 ] ])
  end

  it 'falls back to dacsports.net for an unknown audience' do
    expect(described_class.new(source: "embed:https://anything.example").source).to eq(ReportsQuery::ON_SITE)
  end
end
