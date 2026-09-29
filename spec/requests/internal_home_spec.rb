require 'rails_helper'

RSpec.describe "Internal::Home", type: :request do
  before { sign_in_as create(:user) }

  it "shows who is watching right now" do
    event = create(:event, :live, title: "Tonight Game")
    create(:event_visit, :live, event: event, last_seen_at: 1.minute.ago)

    get internal_root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Tonight Game")
  end

  it "leaves out viewers who have gone quiet" do
    event = create(:event, :live, title: "Earlier Game")
    create(:event_visit, :live, event: event, last_seen_at: 10.minutes.ago)

    get internal_root_path

    expect(response.body).to include("No active viewers")
  end

  it "includes partner-site viewers in who is watching now" do
    event = create(:event, :live, title: "Partner Game")
    create(:event_visit, :live, :embedded, event: event, last_seen_at: 1.minute.ago)

    get internal_root_path

    expect(response.body).to include("Partner Game", "1 on partner sites")
  end

  it "links the week's figures to the matching report" do
    get internal_root_path(source: "partners")

    expect(response.body).to include("start_date=#{6.days.ago.to_date}", "source=partners")
  end

  it "shows the week's watch time from Mux Data" do
    event = create(:event, :replay_available, start_at: 3.days.ago)
    MuxDailyStat.create!(day: 1.day.ago.to_date, video_id: event.slug, event_id: event.id, audience: "dsn",
                         stream_type: "vod", views: 1, unique_viewers: 1, watch_time_ms: 5_400_000)

    get internal_root_path

    expect(response.body).to include("Watch Time", "1.5", "Today fills in after each show")
  end
end
