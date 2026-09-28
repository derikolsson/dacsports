require 'rails_helper'

RSpec.describe ApplicationHelper do
  describe 'Mux Data tagging' do
    let(:event) { build(:event, slug: "final", sport: "Baseball") }

    before { Current.session = build(:session, visitor_id: "3f0e8a3c-0000-4000-8000-000000000001") }

    it 'tags on-site views with the audience, status, sport and visitor' do
      html = helper.mux_player(playback_id: "abc", title: "Final", video_id: "final",
                               analytics: helper.mux_analytics(event, "vod"))

      expect(html).to include('metadata-player-name="dsn-site"', 'metadata-custom-1="dsn"', 'metadata-custom-2="vod"',
                              'metadata-custom-3="Baseball"',
                              %(metadata-viewer-user-id="#{helper.mux_viewer_id("3f0e8a3c-0000-4000-8000-000000000001")}"))
      expect(html).to include("@mux/mux-player@3")
    end

    it 'tags embed views with the partner property' do
      html = helper.signed_mux_player(playback_id: "abc", tokens: {}, title: "Final", video_id: "final",
                                      stream_type: "live",
                                      analytics: helper.mux_analytics(event, "live", source: "embed:https://northlake.example.edu"))

      expect(html).to include('metadata-player-name="dsn-embed"', 'metadata-custom-1="embed:https://northlake.example.edu"')
    end

    it 'never puts the visitor cookie value in the page' do
      html = helper.mux_player(playback_id: "abc", title: "Final", video_id: "final",
                               analytics: helper.mux_analytics(event, "vod"))

      expect(html).not_to include("3f0e8a3c-0000-4000-8000-000000000001")
    end

    it 'leaves out what it does not know' do
      Current.session = nil
      html = helper.mux_player(playback_id: "abc", title: "Final", video_id: "final",
                               analytics: helper.mux_analytics(build(:event, sport: nil), "live"))

      expect(html).not_to include("metadata-viewer-user-id", "metadata-custom-3")
    end
  end
end
