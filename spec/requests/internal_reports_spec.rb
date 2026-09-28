require 'rails_helper'

RSpec.describe "Internal::Reports", type: :request do
  before { sign_in_as create(:user, :admin) }

  # The case that read zero: a partner page featuring a game months after it was played.
  it "shows a partner's replay views of an old event" do
    event = create(:event, :replay_available, title: "District Championship", start_at: 100.days.ago)
    create(:event_visit, :vod, :embedded, event: event, started_at: 1.day.ago)

    get internal_reports_path(start_date: 120.days.ago.to_date, end_date: Date.current,
                              source: "embed:https://northlake.example.edu", basis: "aired")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("District Championship", "VOD - All")
    expect(response.body).to include("0 within 30 days of the event")
    expect(response.body).to match(%r{vod-all group-start">1</td>})
  end

  it "counts this period's replays of older events by default, and says so" do
    event = create(:event, :replay_available, title: "Spring Final", start_at: 100.days.ago)
    create(:event_visit, :vod, event: event, started_at: 1.day.ago)

    get internal_reports_path

    expect(response.body).to include("Spring Final", "including replays of events that aired earlier")
    expect(response.body).not_to include("VOD - 30D")
  end

  it "hides those replays when counting by events aired" do
    event = create(:event, :replay_available, title: "Spring Final", start_at: 100.days.ago)
    create(:event_visit, :vod, event: event, started_at: 1.day.ago)

    get internal_reports_path(basis: "aired")

    expect(response.body).not_to include("Spring Final")
    expect(response.body).to include("No events aired in the selected period.")
  end

  it "totals the per-event table" do
    2.times do |i|
      event = create(:event, :replay_available, title: "Game #{i}", start_at: 3.days.ago)
      create(:event_visit, :vod, event: event, started_at: 1.day.ago)
    end

    get internal_reports_path

    expect(response.body).to include("Total of 2 events")
    expect(response.body).to match(%r{<td class="text-end vod-all">2</td>})
  end

  it "compares the summary with the previous period" do
    event = create(:event, :replay_available, start_at: 60.days.ago)
    create(:event_visit, :vod, event: event, started_at: 40.days.ago)
    2.times { create(:event_visit, :vod, event: event, started_at: 1.day.ago) }

    get internal_reports_path

    expect(response.body).to include("▲ 100%")
  end
end
