require 'rails_helper'

RSpec.describe "Internal::EmbedSettings", type: :request do
  let(:credentials) { Rails.application.credentials.internal_auth || {} }
  let(:auth_headers) do
    {
      "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(
        credentials[:username], credentials[:password]
      )
    }
  end

  after { Dacsports.redis.del(EmbedFrameAncestors::REDIS_KEY) }

  it "requires authentication" do
    get internal_embed_settings_path
    expect(response).to have_http_status(:unauthorized)
  end

  it "says plainly when embedding is blocked everywhere" do
    get internal_embed_settings_path, headers: auth_headers

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Embedding is currently blocked everywhere")
  end

  it "saves partner sites and serves them on the embed route" do
    patch internal_embed_settings_path,
          params: { embed_frame_ancestors: { raw: "https://athletics.northlake.example.edu\nhttps://*.northlake.example.edu" } },
          headers: auth_headers

    expect(response).to redirect_to(internal_embed_settings_path)
    expect(EmbedFrameAncestors.header_value)
      .to eq("https://athletics.northlake.example.edu https://*.northlake.example.edu")

    event = create(:event, :signed_replay)
    get embed_path(event.slug)
    expect(response.headers["Content-Security-Policy"])
      .to eq("frame-ancestors https://athletics.northlake.example.edu https://*.northlake.example.edu")
  end

  it "refuses an entry that would inject extra CSP directives, leaving the list untouched" do
    EmbedFrameAncestors.new(raw: "https://good.example.org").save

    patch internal_embed_settings_path,
          params: { embed_frame_ancestors: { raw: "https://evil.org; default-src *" } },
          headers: auth_headers

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("is not a valid origin")
    expect(EmbedFrameAncestors.header_value).to eq("https://good.example.org")
  end

  it "returns to blocked when the list is emptied" do
    EmbedFrameAncestors.new(raw: "https://a.example.org").save

    patch internal_embed_settings_path,
          params: { embed_frame_ancestors: { raw: "" } },
          headers: auth_headers

    expect(EmbedFrameAncestors.header_value).to eq("'none'")
  end
end
