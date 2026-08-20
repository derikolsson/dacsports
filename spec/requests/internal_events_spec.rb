require 'rails_helper'

RSpec.describe "Internal::Events", type: :request do
  let(:credentials) { Rails.application.credentials.internal_auth || {} }
  let(:auth_headers) do
    {
      "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(
        credentials[:username], credentials[:password]
      )
    }
  end

  describe "POST /internal/events/:id/resolve_signed_playback" do
    let(:event) { create(:event, :signed_replay, mux_asset_id: "SOMEASSETID") }

    it "requires authentication" do
      post resolve_signed_playback_internal_event_path(event)
      expect(response).to have_http_status(:unauthorized)
    end

    it "stores the signed playback ID resolved from the asset" do
      allow(MuxSignedPlaybackId).to receive(:for_asset).with("SOMEASSETID").and_return("NEWSIGNEDID")

      post resolve_signed_playback_internal_event_path(event), headers: auth_headers

      expect(response).to redirect_to(edit_internal_event_path(event))
      expect(event.reload.mux_replay_signed_playback_id).to eq("NEWSIGNEDID")
    end

    it "asks for an asset ID when none is saved" do
      event.update_columns(mux_asset_id: nil)
      expect(MuxSignedPlaybackId).not_to receive(:for_asset)

      post resolve_signed_playback_internal_event_path(event), headers: auth_headers

      expect(response).to redirect_to(edit_internal_event_path(event))
      expect(flash[:alert]).to match(/Asset ID/i)
    end

    # A bad asset ID is an ordinary operator typo, not a 500.
    it "reports a Mux failure without blowing up" do
      allow(MuxSignedPlaybackId).to receive(:for_asset)
        .and_raise(MuxSignedPlaybackId::Error, "Mux asset NOPE: not found")

      post resolve_signed_playback_internal_event_path(event), headers: auth_headers

      expect(response).to redirect_to(edit_internal_event_path(event))
      expect(flash[:alert]).to match(/Could not resolve/)
    end
  end

  describe "GET /internal/events/archive" do
    it "shows embed readiness so it can be checked without opening Mux" do
      create(:event, :signed_replay, title: "Provisioned Game")
      create(:event, :replay_available, title: "Unprovisioned Game")

      get archive_internal_events_path, headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Ready")
      expect(response.body).to include("No signed ID")
    end

    it "offers the partner snippet for a provisioned event" do
      event = create(:event, :signed_replay, title: "Brookhaven vs Richland", sport: "Men's Soccer")

      get archive_internal_events_path, headers: auth_headers

      snippet = CGI.unescapeHTML(response.body)
      expect(snippet).to include("embed.js")
      expect(snippet).to include(%(data-stream="#{event.slug}"))
    end

    # These get copied several at a time into an email, where one bare script tag looks
    # exactly like the next.
    it "names the event in a comment above the snippet" do
      create(:event, :signed_replay, title: "Brookhaven vs Richland", sport: "Men's Soccer",
                                     start_at: 3.days.ago.change(hour: 19))

      get archive_internal_events_path, headers: auth_headers

      expect(CGI.unescapeHTML(response.body))
        .to include("<!-- Men's Soccer: Brookhaven vs Richland — #{3.days.ago.strftime('%b %-d, %Y')} -->")
    end
  end
end
