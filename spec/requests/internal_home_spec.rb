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

    expect(response.body).not_to include("Earlier Game")
  end

  it "includes partner-site viewers in who is watching now" do
    event = create(:event, :live, title: "Partner Game")
    create(:event_visit, :live, :embedded, event: event, last_seen_at: 1.minute.ago)

    get internal_root_path

    expect(response.body).to include("Partner Game", "1 on partner sites")
  end

  it "links the week's figures to the matching report" do
    get internal_root_path(source: "partners")

    expect(response.body).to include("start_date=#{6.days.ago.to_date}", "source=partners", "basis=activity")
  end
end
