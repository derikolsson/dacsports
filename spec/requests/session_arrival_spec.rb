require 'rails_helper'

RSpec.describe "Session arrival", type: :request do
  it "records where a new on-site session came from" do
    get root_path(utm_source: "newsletter", utm_medium: "email", utm_campaign: "homecoming"),
        headers: { "Referer" => "https://mail.example.com/inbox" }

    expect(Session.last).to have_attributes(
      landing_referrer_host: "mail.example.com", landing_path: "/",
      utm_source: "newsletter", utm_medium: "email", utm_campaign: "homecoming"
    )
  end

  it "does not count our own pages as a referrer" do
    get root_path, headers: { "Referer" => "http://www.example.com/events" }

    expect(Session.last.landing_referrer_host).to be_nil
  end

  it "keeps the arrival when the session carries on" do
    get root_path(utm_source: "newsletter")
    get root_path

    expect(Session.count).to eq(1)
    expect(Session.last.utm_source).to eq("newsletter")
  end

  it "records none for embed sessions, whose context is kept per visit" do
    event = create(:event, :signed_replay)
    get embed_path(event.slug, utm_source: "x"), headers: { "Referer" => "https://northlake.example.edu/live" }

    expect(Session.last).to have_attributes(landing_path: nil, utm_source: nil, landing_referrer_host: nil)
  end

  it "gives crawlers no session" do
    expect {
      get root_path, headers: { "User-Agent" => "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)" }
    }.not_to change(Session, :count)

    expect(response).to have_http_status(:ok)
  end
end
