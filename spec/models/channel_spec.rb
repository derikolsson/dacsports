require 'rails_helper'

RSpec.describe Channel, type: :model do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }

    it 'stores a blank stream ID as nil so several unlinked channels can coexist' do
      create(:channel, mux_live_stream_id: " ")
      expect(build(:channel, mux_live_stream_id: "")).to be_valid
    end

    it 'rejects a stream ID another channel already has' do
      create(:channel, mux_live_stream_id: "LS1")
      expect(build(:channel, mux_live_stream_id: "LS1")).not_to be_valid
    end
  end

  it 'refuses to delete a channel events still air on' do
    channel = create(:channel)
    create(:event, channel: channel)

    expect(channel.destroy).to be(false)
  end

  describe '#sync_from_mux!' do
    let(:channel) { create(:channel, mux_live_stream_id: "LS1", mux_live_playback_id: nil, mux_live_signed_playback_id: nil) }
    let(:api) { instance_double(MuxRuby::LiveStreamsApi) }

    before { allow(MuxRuby::LiveStreamsApi).to receive(:new).and_return(api) }

    it 'stores the public playback ID and the signed one' do
      stream = double(playback_ids: [ double(policy: "signed", id: "SIGNED"), double(policy: "public", id: "PUBLIC") ])
      allow(api).to receive(:get_live_stream).with("LS1").and_return(double(data: stream))
      allow(MuxSignedPlaybackId).to receive(:for_live_stream).with("LS1").and_return("SIGNED")

      channel.sync_from_mux!

      expect(channel.reload).to have_attributes(mux_live_playback_id: "PUBLIC", mux_live_signed_playback_id: "SIGNED")
    end

    it 'wraps a Mux failure' do
      allow(api).to receive(:get_live_stream).and_raise(MuxRuby::ApiError.new(message: "not found"))

      expect { channel.sync_from_mux! }.to raise_error(Channel::SyncError, /LS1/)
    end
  end
end
