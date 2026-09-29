require 'rails_helper'

RSpec.describe "Internal::Events", type: :request do
  before { sign_in_as create(:user) }

  describe "POST /internal/events/:id/resolve_signed_playback" do
    let(:event) { create(:event, :signed_replay, mux_asset_id: "SOMEASSETID") }

    it "stores the signed playback ID resolved from the asset" do
      allow(MuxSignedPlaybackId).to receive(:for_asset).with("SOMEASSETID").and_return("NEWSIGNEDID")

      post resolve_signed_playback_internal_event_path(event)

      expect(response).to redirect_to(edit_internal_event_path(event))
      expect(event.reload.mux_replay_signed_playback_id).to eq("NEWSIGNEDID")
    end

    it "asks for an asset ID when none is saved" do
      event.update_columns(mux_asset_id: nil)
      expect(MuxSignedPlaybackId).not_to receive(:for_asset)

      post resolve_signed_playback_internal_event_path(event)

      expect(response).to redirect_to(edit_internal_event_path(event))
      expect(flash[:alert]).to match(/Asset ID/i)
    end

    # A bad asset ID is an ordinary operator typo, not a 500.
    it "reports a Mux failure without blowing up" do
      allow(MuxSignedPlaybackId).to receive(:for_asset)
        .and_raise(MuxSignedPlaybackId::Error, "Mux asset NOPE: not found")

      post resolve_signed_playback_internal_event_path(event)

      expect(response).to redirect_to(edit_internal_event_path(event))
      expect(flash[:alert]).to match(/Could not resolve/)
    end
  end

  describe "minting the signed replay ID automatically" do
    let(:event) { create(:event, :replay_pending) }

    it "mints it when an asset ID is saved" do
      allow(MuxSignedPlaybackId).to receive(:for_asset).with("ASSET1").and_return("SIGNED1")

      patch internal_event_path(event), params: { event: { mux_asset_id: "ASSET1" } }

      expect(event.reload.mux_replay_signed_playback_id).to eq("SIGNED1")
    end

    it "mints a new one when the asset changes" do
      event.update!(mux_asset_id: "OLD", mux_replay_signed_playback_id: "OLDSIGNED")
      allow(MuxSignedPlaybackId).to receive(:for_asset).with("NEW").and_return("NEWSIGNED")

      patch internal_event_path(event), params: { event: { mux_asset_id: "NEW" } }

      expect(event.reload.mux_replay_signed_playback_id).to eq("NEWSIGNED")
    end

    it "leaves an existing one alone when the asset is unchanged" do
      event.update!(mux_asset_id: "ASSET1", mux_replay_signed_playback_id: "SIGNED1")
      expect(MuxSignedPlaybackId).not_to receive(:for_asset)

      patch internal_event_path(event), params: { event: { title: "Renamed" } }
    end

    it "keeps the save and warns when Mux refuses" do
      allow(MuxSignedPlaybackId).to receive(:for_asset)
        .and_raise(MuxSignedPlaybackId::Error, "Mux asset NOPE: not found")

      patch internal_event_path(event), params: { event: { mux_asset_id: "NOPE", title: "Renamed" } }

      expect(event.reload).to have_attributes(title: "Renamed", mux_replay_signed_playback_id: nil)
      expect(flash[:alert]).to match(/Could not resolve/)
    end

    it "mints it on publish, which is enough of a replay source to publish from" do
      event.update_columns(mux_asset_id: "ASSET1")
      allow(MuxSignedPlaybackId).to receive(:for_asset).with("ASSET1").and_return("SIGNED1")

      post publish_replay_internal_event_path(event)

      expect(event.reload).to be_replay_available
      expect(event.mux_replay_signed_playback_id).to eq("SIGNED1")
      expect(flash[:alert]).to be_nil
    end

    it "warns on publish when the embed will have nothing to play" do
      event.update_columns(replay_embed_code: "<iframe></iframe>")

      post publish_replay_internal_event_path(event)

      expect(event.reload).to be_replay_available
      expect(flash[:alert]).to match(/Partner embeds/)
    end
  end

  describe "GET /internal/events/new" do
    # The form's "Resolve signed ID" button targets a member route, which an
    # unsaved event has no id for. Rendering must not try to build that path.
    it "renders the form for an unsaved event" do
      get new_internal_event_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Resolve signed ID")
    end
  end

  describe "GET /internal/events/:id/edit" do
    it "links the resolve action for a saved event" do
      event = create(:event)

      get edit_internal_event_path(event)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(resolve_signed_playback_internal_event_path(event))
    end
  end

  describe "GET /internal/events/archive" do
    it "shows embed readiness so it can be checked without opening Mux" do
      create(:event, :signed_replay, title: "Provisioned Game")
      create(:event, :replay_available, title: "Unprovisioned Game")

      get archive_internal_events_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Ready")
      expect(response.body).to include("No signed ID")
    end

    it "offers the partner snippet for a provisioned event" do
      event = create(:event, :signed_replay, title: "Brookhaven vs Richland", sport: "Men's Soccer")

      get archive_internal_events_path

      snippet = CGI.unescapeHTML(response.body)
      expect(snippet).to include("embed.js")
      expect(snippet).to include(%(data-stream="#{event.slug}"))
    end

    # These get copied several at a time into an email, where one bare script tag looks
    # exactly like the next.
    it "names the event in a comment above the snippet" do
      create(:event, :signed_replay, title: "Brookhaven vs Richland", sport: "Men's Soccer",
                                     start_at: 3.days.ago.change(hour: 19))

      get archive_internal_events_path

      expect(CGI.unescapeHTML(response.body))
        .to include("<!-- Men's Soccer: Brookhaven vs Richland — #{3.days.ago.strftime('%b %-d, %Y')} -->")
    end
  end

  describe "GET /internal/events" do
    # A snippet pasted ahead of the game follows the event through to its replay.
    it "offers the partner snippet for an upcoming event" do
      event = create(:event, :upcoming, channel: create(:channel))

      get internal_events_path

      expect(CGI.unescapeHTML(response.body)).to include(%(data-stream="#{event.slug}"))
      expect(response.body).to include("Ready")
    end

    it "marks only the events hidden from the public" do
      create(:event, :hidden, title: "Hidden Game")
      create(:event, title: "Public Game")

      get internal_events_path

      expect(response.body.scan("bi-eye-slash").size).to eq(1)
    end

    it "flags an upcoming event whose channel has no signed live ID" do
      create(:event, :upcoming, channel: create(:channel, mux_live_signed_playback_id: nil))

      get internal_events_path

      expect(response.body).to include("No signed ID")
    end
  end

  describe "channel selection" do
    let(:channel) { create(:channel, name: "Main Court") }
    let(:event) { create(:event) }

    it "offers channels on the form" do
      channel
      get edit_internal_event_path(event)
      expect(response.body).to include("Main Court")
    end

    it "puts the event on the chosen channel" do
      patch internal_event_path(event), params: { event: { channel_id: channel.id } }
      expect(event.reload.mux_live_signed_playback_id).to eq(channel.mux_live_signed_playback_id)
    end
  end
end
