require 'rails_helper'

RSpec.describe "Internal::EmbedPreviews", type: :request do
  let(:credentials) { Rails.application.credentials.internal_auth || {} }
  let(:auth_headers) do
    {
      "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(
        credentials[:username], credentials[:password]
      )
    }
  end

  it "requires authentication" do
    get internal_embed_preview_path
    expect(response).to have_http_status(:unauthorized)
  end

  it "says so when nothing is embeddable yet" do
    create(:event, :replay_available) # published replay, but no signed playback ID

    get internal_embed_preview_path, headers: auth_headers

    expect(response.body).to include("No event is embeddable right now")
  end

  it "previews the most recent embeddable event" do
    create(:event, :signed_replay, title: "Older Game", start_at: 3.weeks.ago)
    newest = create(:event, :signed_replay, title: "Newest Game", start_at: 2.days.ago)

    get internal_embed_preview_path, headers: auth_headers

    expect(response.body).to include("Newest Game")
    expect(response.body).to include(%(data-stream="#{newest.slug}"))
  end

  it "can preview a specific event" do
    create(:event, :signed_replay, title: "Newest Game", start_at: 2.days.ago)
    older = create(:event, :signed_replay, title: "Older Game", start_at: 3.weeks.ago)

    get internal_embed_preview_path(slug: older.slug), headers: auth_headers

    expect(response.body).to include(%(data-stream="#{older.slug}"))
  end

  it "ignores events whose state is playable but have no signed playback ID" do
    create(:event, :replay_available, title: "Unprovisioned")

    get internal_embed_preview_path, headers: auth_headers

    expect(response.body).not_to include("Unprovisioned")
  end

  # The preview frames the embed, and frame-ancestors 'none' would block same-origin
  # framing too — so it has to keep working before any partner is approved.
  it "can frame the embed with no partner sites approved" do
    event = create(:event, :signed_replay)

    get embed_path(event.slug)

    expect(response.headers["Content-Security-Policy"]).to eq("frame-ancestors 'self'")
  end
end
