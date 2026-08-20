require 'rails_helper'

RSpec.describe "Embeds", type: :request do
  before { stub_mux_signing_credentials }

  describe "GET /embed/:slug" do
    context "in a playable state" do
      let(:event) { create(:event, :signed_replay) }

      it "renders a player with all three signed tokens" do
        get embed_path(event.slug)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("<mux-player")
        expect(response.body).to include("playback-token=")
        expect(response.body).to include("thumbnail-token=")
        expect(response.body).to include("storyboard-token=")
      end

      it "marks on-demand content with the right stream type" do
        get embed_path(event.slug)
        expect(response.body).to include('stream-type="on-demand"')
      end

      # @2 resolves to 2.9.1, which fires a stray relative fetch at our own origin on
      # every load. Pinned rather than bare so a new major cannot land unchosen.
      it "pins mux-player to a known-good major" do
        get embed_path(event.slug)

        expect(response.body).to include("@mux/mux-player@3")
        expect(response.body).not_to include("@mux/mux-player@2")
      end

      it "sets an explicit poster using the thumbnail token" do
        get embed_path(event.slug)
        expect(response.body).to match(%r{poster="https://image\.mux\.com/[^"]+token=})
      end

      it "hides casting, which would silently fail under the embed restriction" do
        get embed_path(event.slug)
        expect(response.body).to include("--cast-button: none")
        expect(response.body).to include("--airplay-button: none")
      end
    end

    context "when live" do
      let(:event) { create(:event, :signed_live) }

      it "marks the stream as live" do
        get embed_path(event.slug)
        expect(response.body).to include('stream-type="live"')
      end

      # Mux only generates storyboards for on-demand assets.
      it "omits the storyboard token" do
        get embed_path(event.slug)

        expect(response.body).to include("playback-token=")
        expect(response.body).not_to include("storyboard-token=")
      end
    end

    # The reload is an enforcement mechanism: it is how a viewer gets pulled off a
    # player they should not be seeing. If a reload re-signed, it would just hand the
    # viewer a fresh token, so these states must issue nothing.
    context "in a non-playable state" do
      %i[upcoming ended replay_pending technical_difficulties].each do |state|
        it "issues no token and renders no player when #{state}" do
          event = create(:event, state)

          get embed_path(event.slug)

          expect(response).to have_http_status(:ok)
          expect(response.body).not_to include("playback-token=")
          expect(response.body).not_to include("<mux-player")
          expect(response.body).to include("embed-slate")
        end
      end
    end

    it "issues no token when the event has no signed playback id" do
      event = create(:event, :replay_available)

      get embed_path(event.slug)

      expect(response.body).not_to include("playback-token=")
    end

    describe "framing headers" do
      let(:event) { create(:event, :signed_replay) }

      # SAMEORIGIN is a Rails default and is live in production; it would block every
      # partner page.
      it "does not send X-Frame-Options" do
        get embed_path(event.slug)
        expect(response.headers["X-Frame-Options"]).to be_nil
      end

      it "ships closed: our own origin only, no partners" do
        get embed_path(event.slug)
        expect(response.headers["Content-Security-Policy"]).to eq("frame-ancestors 'self'")
      end

      # The wrong direction here silently opens the route to anyone, so an outage must
      # deny rather than guess.
      it "fails closed when Redis is unreachable" do
        allow(Dacsports.redis).to receive(:get).and_raise(Redis::CannotConnectError)

        get embed_path(event.slug)

        expect(response).to have_http_status(:ok)
        expect(response.headers["Content-Security-Policy"]).to eq("frame-ancestors 'self'")
      end

      it "uses the configured partner list when one is set" do
        Dacsports.redis.set("embed_frame_ancestors", "https://northlake.example.edu")
        get embed_path(event.slug)

        expect(response.headers["Content-Security-Policy"]).to eq("frame-ancestors 'self' https://northlake.example.edu")
      ensure
        Dacsports.redis.del("embed_frame_ancestors")
      end
    end

    describe "visibility" do
      # Preview is an internal affordance and must not be reachable from a partner page.
      it "does not honour ?preview=true on a hidden event" do
        event = create(:event, :signed_replay, :hidden)

        get embed_path(event.slug), params: { preview: "true" }

        expect(response).to have_http_status(:not_found)
        expect(response.body).not_to include("playback-token=")
      end

      it "404s a hidden event" do
        event = create(:event, :signed_replay, :hidden)

        get embed_path(event.slug)

        expect(response).to have_http_status(:not_found)
      end

      it "404s an unknown slug" do
        get embed_path("no-such-event")
        expect(response).to have_http_status(:not_found)
      end
    end

    # These predate generating the player from Mux IDs. Rendering them would bypass
    # signing entirely and inject html_safe admin markup into a frame we vouch for.
    it "never renders the legacy embed code fields" do
      event = create(:event, :replay_available,
                     replay_embed_code: "<iframe src='https://elsewhere.example.com/x'></iframe>")

      get embed_path(event.slug)

      expect(response.body).not_to include("elsewhere.example.com")
    end

    it "redirects a retired slug to the current one" do
      event = create(:event, :signed_replay, slug: "old-slug")
      event.update!(slug: "new-slug")

      get embed_path("old-slug")

      expect(response).to have_http_status(:moved_permanently)
      expect(response).to redirect_to(embed_path("new-slug"))
    end

    it "does not reflect attacker-controlled parent params into the page" do
      event = create(:event, :signed_replay)

      get embed_path(event.slug), params: {
        src: "https://evil.example.com/<script>alert(1)</script>",
        title: "<script>alert(2)</script>"
      }

      expect(response.body).not_to include("alert(1)")
      expect(response.body).not_to include("alert(2)")
      expect(response.body).not_to include("evil.example.com")
    end
  end

  describe "POST /embed/:slug/status" do
    let(:event) { create(:event, :signed_replay) }
    let(:session) { create(:session) }

    it "returns the current state for the poller" do
      post embed_status_path(event.slug), params: { session_id: session.id }, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["status"]).to eq("replay_available")
      expect(body["force_reload_version"]).to eq(event.force_reload_count)
      expect(body["ttl"]).to be_present
    end

    it "404s a hidden event so the poller reloads into the denial state" do
      hidden = create(:event, :signed_replay, :hidden)

      post embed_status_path(hidden.slug), params: { session_id: session.id }, as: :json

      expect(response).to have_http_status(:not_found)
    end


    # Only the initial page load sees the partner's Referer; the poller's request comes
    # from inside the frame and is same-origin. Without carrying it forward, every embed
    # visit would be credited to us instead of the partner.
    it "attributes a poll to the partner that loaded the page, not to the frame" do
      get embed_path(event.slug), headers: { "Referer" => "https://northlake.example.edu/athletics/live" }
      token = response.body[/sourceToken: "([^"]+)"/, 1]
      expect(token).to be_present

      expect(EventVisitJob).to receive(:perform_async).with(
        anything, event.id, "vod", anything, anything,
        "embed:https://northlake.example.edu", "https://northlake.example.edu"
      )

      # As the in-frame poller does: same-origin, no partner referer, no cookies needed.
      post embed_status_path(event.slug),
           params: { session_id: Session.last.id, enabled: "true", source_token: token },
           headers: { "Referer" => "http://www.example.com/embed/#{event.slug}" },
           as: :json
    end

    # A plain param would let any parent page claim another property's traffic. The
    # token is only ever minted server-side from a Referer we actually saw.
    it "rejects a forged source token rather than trusting it" do
      expect(EventVisitJob).to receive(:perform_async).with(
        anything, event.id, "vod", anything, anything, "embed", nil
      )

      post embed_status_path(event.slug),
           params: { session_id: session.id, enabled: "true",
                     source_token: "not-a-real-token--#{Base64.strict_encode64('{"origin":"https://someone-else.org"}')}" },
           as: :json
    end

    it "records no partner when no token is supplied" do
      expect(EventVisitJob).to receive(:perform_async).with(
        anything, event.id, "vod", anything, anything, "embed", nil
      )

      post embed_status_path(event.slug),
           params: { session_id: session.id, enabled: "true" },
           headers: { "Referer" => "http://www.example.com/embed/#{event.slug}" },
           as: :json
    end

    # Attribution must survive a viewer who blocks third-party cookies, which Safari
    # does by default — the reason this is a signed token and not a cookie.
    it "attributes correctly with no cookies at all" do
      get embed_path(event.slug), headers: { "Referer" => "https://northlake.example.edu/live" }
      token = response.body[/sourceToken: "([^"]+)"/, 1]
      session_id = Session.last.id

      expect(EventVisitJob).to receive(:perform_async).with(
        anything, event.id, "vod", anything, anything,
        "embed:https://northlake.example.edu", "https://northlake.example.edu"
      )

      reset!  # drops the cookie jar
      post embed_status_path(event.slug),
           params: { session_id: session_id, enabled: "true", source_token: token },
           as: :json
    end

    it "does not record a visit without a session id" do
      expect(EventVisitJob).not_to receive(:perform_async)

      post embed_status_path(event.slug), params: { enabled: "true" }, as: :json
    end
  end

  describe "visitor identity" do
    let(:event) { create(:event, :signed_replay) }

    # The site's visitor_id cookie is SameSite=Lax and is never sent in a cross-site
    # frame, so the embed needs its own. Partitioned because that is the only third-party
    # cookie form Chrome still honours.
    it "sets a partitioned embed cookie scoped to the embed path" do
      get embed_path(event.slug)

      cookie = response.headers["Set-Cookie"].to_s
      expect(cookie).to include("embed_visitor_id")
      expect(cookie).to match(/path=\/embed/i)
      expect(cookie).to match(/samesite=none/i)
      expect(cookie).to match(/partitioned/i)
    end

    it "reuses the session for a returning viewer instead of minting a new one" do
      get embed_path(event.slug)
      visitor = cookies[:embed_visitor_id]
      expect(visitor).to be_present

      expect { 3.times { get embed_path(event.slug) } }.not_to change(Session, :count)
    end

    # embed.js is fetched on every partner page view, whether or not anyone watches. A
    # session per fetch would badly inflate the sessions table and every unique built on
    # it.
    it "creates no session for embed.js" do
      expect { get embed_script_path }.not_to change(Session, :count)
    end

    it "creates no session for an unknown slug" do
      expect { get embed_path("no-such-event") }.not_to change(Session, :count)
    end

    it "creates no session for a hidden event" do
      hidden = create(:event, :signed_replay, :hidden)
      expect { get embed_path(hidden.slug) }.not_to change(Session, :count)
    end

    # The wrapper writes this id to the PARTNER page's own localStorage, making it
    # first-party there. That is what survives third-party cookie blocking, which
    # otherwise made every frame load look like a brand new viewer.
    it "reuses the visitor id supplied by the wrapper" do
      vid = SecureRandom.uuid

      get embed_path(event.slug), params: { v: vid }
      expect(Session.last.visitor_id).to eq(vid)

      expect { get embed_path(event.slug), params: { v: vid } }.not_to change(Session, :count)
    end

    it "ignores a malformed visitor id rather than storing it" do
      get embed_path(event.slug), params: { v: "not-a-uuid'; DROP TABLE" }

      expect(response).to have_http_status(:ok)
      expect(Session.last.visitor_id).to match(/\A[0-9a-f-]{36}\z/)
    end

    # The poller carries no visitor identity of its own; it echoes the session from page
    # load. Establishing one here would mint a fresh Session on every poll.
    it "creates no session when the poller checks in" do
      get embed_path(event.slug)
      session_id = Session.last.id

      expect {
        3.times do
          post embed_status_path(event.slug), params: { session_id: session_id }, as: :json
        end
      }.not_to change(Session, :count)
    end

    it "creates a session for a real view" do
      expect { get embed_path(event.slug) }.to change(Session, :count).by(1)
    end

    # The poller posts this straight back as session_id, and EventVisit belongs_to
    # :session — handing it the cookie UUID instead would fail the association and
    # silently drop every embed visit.
    it "hands the poller a real session id, not the cookie value" do
      get embed_path(event.slug)

      session_id = Session.last.id
      expect(response.body).to include(%(sessionId: "#{session_id}"))
      expect(response.body).not_to include(cookies[:embed_visitor_id].to_s)
    end
  end

  describe "GET /embed.js" do
    it "serves the wrapper as javascript" do
      get embed_script_path

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/javascript")
      expect(response.body).to include("data-stream")
    end

    # The whole reason the wrapper was chosen over a raw iframe is that a fix can
    # propagate same-day. A long cache would defeat that.
    it "sets a short public cache so a fix propagates same-day" do
      get embed_script_path
      expect(response.headers["Cache-Control"]).to include("max-age=300")
    end

    # Framing the host that served the script keeps the wrapper self-consistent and
    # lets it be exercised against staging rather than only production.
    it "derives the iframe origin from its own script src" do
      get embed_script_path
      expect(response.body).to include("new URL(script.src")
    end

    it "sets the iframe allow attribute, without which fullscreen and PiP die silently" do
      get embed_script_path

      expect(response.body).to include("autoplay")
      expect(response.body).to include("fullscreen")
      expect(response.body).to include("picture-in-picture")
      expect(response.body).to include("remote-playback")
    end
  end
end
