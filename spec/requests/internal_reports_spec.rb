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

  it "exports the report as CSV" do
    event = create(:event, :replay_available, title: "Spring Final", start_at: 3.days.ago)
    create(:event_visit, :vod, event: event, started_at: 1.day.ago)

    get internal_reports_path(format: :csv)

    expect(response.media_type).to eq("text/csv")
    expect(response.headers["Content-Disposition"]).to include("dsn-viewership-")
    expect(response.body).to include("Spring Final")
  end

  it "narrows to a team and keeps that on the preset links" do
    team = create(:team, name: "Brookhaven")
    ours = create(:event, :replay_available, title: "Bears Home Game", start_at: 3.days.ago)
    ours.event_teams.create!(team: team)
    create(:event_visit, :vod, event: ours, started_at: 1.day.ago)
    theirs = create(:event, :replay_available, title: "Someone Else", start_at: 3.days.ago)
    create(:event_visit, :vod, event: theirs, started_at: 1.day.ago)

    get internal_reports_path(team_id: team.id)

    expect(response.body).to include("Bears Home Game", "Only Brookhaven events.")
    expect(response.body).not_to include("Someone Else")
    expect(response.body).to include("team_id=#{team.id}")
  end

  it "sorts the per-event table by a column" do
    quiet = create(:event, :replay_available, title: "Quiet Game", start_at: 5.days.ago)
    busy = create(:event, :replay_available, title: "Busy Game", start_at: 4.days.ago)
    create(:event_visit, :vod, event: quiet, started_at: 1.day.ago)
    2.times { create(:event_visit, :vod, event: busy, started_at: 1.day.ago) }

    get internal_reports_path(sort: "vod_all_views", direction: "desc")
    expect(response.body.index("Busy Game")).to be < response.body.index("Quiet Game")

    # An unknown column falls back to air date, oldest first.
    get internal_reports_path(sort: "DROP TABLE")
    expect(response.body.index("Quiet Game")).to be < response.body.index("Busy Game")
  end

  it "compares partner sites when showing all partners" do
    event = create(:event, :replay_available, start_at: 3.days.ago)
    create(:event_visit, :vod, :embedded, event: event, started_at: 1.day.ago)

    get internal_reports_path(source: "partners")

    expect(response.body).to include("By Partner Site", "https://northlake.example.edu", "100.0%")
  end

  it "compares player time in hours with the previous period's hours" do
    event = create(:event, :replay_available, start_at: 60.days.ago)
    create(:event_visit, :vod, event: event, started_at: 40.days.ago, last_seen_at: 40.days.ago + 2.hours)
    create(:event_visit, :vod, event: event, started_at: 2.days.ago, last_seen_at: 2.days.ago + 3.hours)

    get internal_reports_path

    expect(response.body).to include("3 hours", "vs 2 previous period")
  end

  it "lists partner pages, escaping what the partner page supplied" do
    event = create(:event, :replay_available, start_at: 3.days.ago)
    create(:event_visit, :vod, :embedded, event: event, started_at: 1.day.ago,
                                          page_url: "https://northlake.example.edu/live", page_title: "<b>Live</b>")

    get internal_reports_path(source: "partners")

    expect(response.body).to include("Top Partner Pages", "&lt;b&gt;Live&lt;/b&gt;")
  end
end
