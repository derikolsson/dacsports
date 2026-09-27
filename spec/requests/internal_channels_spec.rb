require 'rails_helper'

RSpec.describe "Internal::Channels", type: :request do
  let(:credentials) { Rails.application.credentials.internal_auth || {} }
  let(:auth_headers) do
    {
      "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(
        credentials[:username], credentials[:password]
      )
    }
  end

  it "requires authentication" do
    get internal_channels_path
    expect(response).to have_http_status(:unauthorized)
  end

  it "lists channels" do
    create(:channel, name: "Main Court")
    get internal_channels_path, headers: auth_headers
    expect(response.body).to include("Main Court")
  end

  describe "POST /internal/channels" do
    it "creates the channel and syncs it from Mux" do
      expect_any_instance_of(Channel).to receive(:sync_from_mux!)

      post internal_channels_path, params: { channel: { name: "Main Court", mux_live_stream_id: "LS1" } }, headers: auth_headers

      expect(response).to redirect_to(internal_channels_path)
      expect(Channel.find_by(mux_live_stream_id: "LS1").name).to eq("Main Court")
    end

    it "keeps the channel but reports a failed sync" do
      allow_any_instance_of(Channel).to receive(:sync_from_mux!).and_raise(Channel::SyncError, "not found")

      post internal_channels_path, params: { channel: { name: "Main Court", mux_live_stream_id: "LS1" } }, headers: auth_headers

      channel = Channel.find_by(mux_live_stream_id: "LS1")
      expect(response).to redirect_to(edit_internal_channel_path(channel))
      expect(flash[:alert]).to match(/not found/)
    end

    it "re-renders the form when invalid" do
      post internal_channels_path, params: { channel: { name: "" } }, headers: auth_headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  it "won't delete a channel with events" do
    channel = create(:channel)
    create(:event, channel: channel)

    delete internal_channel_path(channel), headers: auth_headers

    expect(Channel.exists?(channel.id)).to be(true)
    expect(flash[:alert]).to be_present
  end
end
