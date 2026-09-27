require 'rails_helper'

RSpec.describe "Internal::Channels", type: :request do
  before { sign_in_as create(:user, :admin) }

  it "lists channels" do
    create(:channel, name: "Main Court")
    get internal_channels_path
    expect(response.body).to include("Main Court")
  end

  describe "POST /internal/channels" do
    it "creates the channel and syncs it from Mux" do
      expect_any_instance_of(Channel).to receive(:sync_from_mux!)

      post internal_channels_path, params: { channel: { mux_live_stream_id: "LS1" } }

      expect(response).to redirect_to(internal_channels_path)
      expect(Channel.find_by(mux_live_stream_id: "LS1")).to be_present
    end

    it "keeps the channel but reports a failed sync" do
      allow_any_instance_of(Channel).to receive(:sync_from_mux!).and_raise(Channel::SyncError, "not found")

      post internal_channels_path, params: { channel: { mux_live_stream_id: "LS1" } }

      channel = Channel.find_by(mux_live_stream_id: "LS1")
      expect(response).to redirect_to(edit_internal_channel_path(channel))
      expect(flash[:alert]).to match(/not found/)
    end

    it "saves captions and the channel's own vocabulary" do
      allow_any_instance_of(Channel).to receive(:sync_from_mux!)

      post internal_channels_path, params: {
        channel: { mux_live_stream_id: "LS1", captions_enabled: "1",
                   vocabulary_attributes: { phrases: "Main Court" } }
      }

      channel = Channel.find_by(mux_live_stream_id: "LS1")
      expect(channel.captions_enabled).to be(true)
      expect(channel.vocabulary.phrase_list).to eq([ "Main Court" ])
      expect(SyncChannelCaptionsJob.jobs.size).to eq(1)
    end

    it "skips an empty channel vocabulary" do
      allow_any_instance_of(Channel).to receive(:sync_from_mux!)

      post internal_channels_path, params: {
        channel: { mux_live_stream_id: "LS1", vocabulary_attributes: { phrases: "" } }
      }

      expect(Channel.find_by(mux_live_stream_id: "LS1").vocabulary).to be_nil
    end

    it "re-renders the form when invalid" do
      post internal_channels_path, params: { channel: { mux_live_stream_id: "" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  it "renders the edit form with caption settings" do
    channel = create(:channel, captions_enabled: true, captions_sync_error: "The stream is live")
    get edit_internal_channel_path(channel)
    expect(response.body).to include("Extra vocabulary", "The stream is live")
  end

  it "won't delete a channel with events" do
    channel = create(:channel)
    create(:event, channel: channel)

    delete internal_channel_path(channel)

    expect(Channel.exists?(channel.id)).to be(true)
    expect(flash[:alert]).to be_present
  end
end
