require 'rails_helper'

RSpec.describe Channel, type: :model do
  describe 'validations' do
    it 'needs a Mux live stream ID' do
      expect(build(:channel, mux_live_stream_id: " ")).not_to be_valid
    end

    it 'goes by the stream ID until Mux supplies a title' do
      expect(create(:channel, name: nil, mux_live_stream_id: "LS1").name).to eq("LS1")
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

    it 'stores the stream title, the public playback ID, and the signed one' do
      stream = double(meta: double(title: "DAC Sports 1"),
                      playback_ids: [ double(policy: "signed", id: "SIGNED"), double(policy: "public", id: "PUBLIC") ])
      allow(api).to receive(:get_live_stream).with("LS1").and_return(double(data: stream))
      allow(MuxSignedPlaybackId).to receive(:for_live_stream).with("LS1").and_return("SIGNED")

      channel.sync_from_mux!

      expect(channel.reload).to have_attributes(
        name: "DAC Sports 1", mux_live_playback_id: "PUBLIC", mux_live_signed_playback_id: "SIGNED"
      )
    end

    it 'keeps the current name when the stream has no title' do
      stream = double(meta: nil, playback_ids: [])
      allow(api).to receive(:get_live_stream).and_return(double(data: stream))
      allow(MuxSignedPlaybackId).to receive(:for_live_stream).and_return("SIGNED")

      expect { channel.sync_from_mux! }.not_to change { channel.reload.name }
    end

    it 'wraps a Mux failure' do
      allow(api).to receive(:get_live_stream).and_raise(MuxRuby::ApiError.new(message: "not found"))

      expect { channel.sync_from_mux! }.to raise_error(Channel::SyncError, /LS1/)
    end
  end

  describe '#sync_captions_to_mux!' do
    let(:channel) { create(:channel, mux_live_stream_id: "LS1", captions_enabled: true) }
    let(:api) { instance_double(MuxRuby::LiveStreamsApi) }
    let(:stream) { double(status: "idle", latency_mode: "standard") }

    before do
      allow(MuxRuby::LiveStreamsApi).to receive(:new).and_return(api)
      allow(api).to receive(:get_live_stream).with("LS1").and_return(double(data: stream))
      create(:vocabulary, mux_vocabulary_id: "GLOBALVOCAB")
    end

    it 'attaches the shared vocabulary, then the channel one' do
      create(:vocabulary, channel: channel, mux_vocabulary_id: "CHANNELVOCAB")
      expect(api).to receive(:update_live_stream_generated_subtitles) do |id, request|
        expect(id).to eq("LS1")
        expect(request.generated_subtitles.first).to have_attributes(
          language_code: "en", transcription_vocabulary_ids: %w[GLOBALVOCAB CHANNELVOCAB]
        )
      end

      channel.sync_captions_to_mux!

      expect(channel.reload.captions_synced_at).to be_present
    end

    it 'clears the generated captions when they are turned off' do
      channel.update_columns(captions_enabled: false)
      expect(api).to receive(:update_live_stream_generated_subtitles) do |_id, request|
        expect(request.generated_subtitles).to eq([])
      end

      channel.sync_captions_to_mux!
    end

    it 'refuses a low-latency stream' do
      allow(stream).to receive(:latency_mode).and_return("low")

      expect { channel.sync_captions_to_mux! }.to raise_error(Channel::SyncError, /low-latency/)
      expect(channel.reload.captions_sync_error).to match(/low-latency/)
    end

    it 'waits for a live stream to go idle' do
      allow(stream).to receive(:status).and_return("active")
      expect { channel.sync_captions_to_mux! }.to raise_error(Channel::StreamActive)
    end
  end

  it 'queues a caption sync when captions are switched' do
    channel = create(:channel)
    expect { channel.update!(captions_enabled: true) }.to change(SyncChannelCaptionsJob.jobs, :size).by(1)
    expect { channel.update!(name: "Renamed") }.not_to change(SyncChannelCaptionsJob.jobs, :size)
  end
end
