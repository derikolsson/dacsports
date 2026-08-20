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

    it 'excludes partner visits from the per-event breakdown' do
      row = report.per_event_stats.find { |r| r["id"] == event.id }
      expect(row["vod_30d_viewers"]).to eq(1)
    end
  end

  describe 'scoped to a partner property' do
    subject(:report) { described_class.new(**range, source: "embed:https://northside.org") }

    it 'counts only that partner’s traffic' do
      expect(report.summary_stats[:vod]).to eq(users: 1, views: 1)
    end

    it 'reports that partner’s devices' do
      expect(report.device_breakdown.keys).to eq([ "Phone" ])
    end

    # The source filter belongs in the LEFT JOIN's ON clause; in WHERE it would drop
    # every event that has no matching visit.
    it 'still lists events with no visits from that partner' do
      quiet = create(:event, :replay_available, start_at: 3.days.ago)
      other = described_class.new(**range, source: "embed:https://someone-else.org")

      expect(other.per_event_stats.map { |r| r["id"] }).to include(quiet.id)
    end
  end
end
