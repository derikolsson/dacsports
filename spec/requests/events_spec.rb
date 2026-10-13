require 'rails_helper'

RSpec.describe "Events", type: :request do
  describe "GET /events/:slug" do
    it "plays a replay from its public playback ID" do
      event = create(:event, :replay_available, replay_embed_code: nil, mux_replay_playback_id: "PUBLICID")

      get event_path(event.slug)

      expect(response.body).to include(%(playback-id="PUBLICID"))
    end

    # A signed ID only plays in partner embeds; the site can't use it.
    it "says the replay is coming rather than showing an empty player when only a signed ID is on file" do
      event = create(:event, :signed_replay)

      get event_path(event.slug)

      expect(response.body).not_to include("<mux-player")
      expect(response.body).to include("A replay of this broadcast will be available shortly")
    end
  end

  describe "link previews" do
    it "shows the logo by default" do
      event = create(:event)

      get event_path(event.slug)

      expect(response.body).to match(%r{<meta property="og:image" content="http://www\.example\.com/assets/logo-\h+\.png">})
      expect(response.body).to include(%(<meta name="twitter:card" content="summary">))
    end

    it "shows the event's poster when it has one" do
      event = create(:event, poster_key: "posters/events/abc.png")

      get event_path(event.slug)

      expect(response.body).to include(%(<meta property="og:image" content="#{EventPoster.url("posters/events/abc.png")}">))
      expect(response.body).to include(%(<meta name="twitter:card" content="summary_large_image">))
    end
  end
end
