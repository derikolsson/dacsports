require 'rails_helper'

RSpec.describe Vocabulary, type: :model do
  let(:api) { instance_double(MuxRuby::TranscriptionVocabulariesApi) }

  before { allow(MuxRuby::TranscriptionVocabulariesApi).to receive(:new).and_return(api) }

  describe '#all_phrases' do
    it 'adds team names and mascots to the shared list' do
      create(:team, name: "Richland", slug: "richland")
      vocabulary = build(:vocabulary, phrases: "DAC Sports\n\n  richland  \nDAC Sports")

      expect(vocabulary.all_phrases).to include("DAC Sports", "Thunderducks", "Harvester Bees")
      expect(vocabulary.all_phrases.count { |p| p.casecmp?("richland") }).to eq(1)
    end

    it 'keeps a channel list to its own phrases' do
      create(:team, name: "Richland")
      expect(build(:vocabulary, :for_channel, phrases: "Main Court").all_phrases).to eq([ "Main Court" ])
    end
  end

  describe 'validations' do
    it 'allows only one shared vocabulary' do
      create(:vocabulary)
      expect(build(:vocabulary)).not_to be_valid
    end

    it 'refuses a channel list that pushes the stream past the Mux phrase cap' do
      create(:vocabulary, phrases: "DAC Sports")
      too_many = (1..Vocabulary::MAX_PHRASES).map { |n| "Phrase #{n}" }.join("\n")

      vocabulary = build(:vocabulary, :for_channel, phrases: too_many)

      expect(vocabulary).not_to be_valid
      expect(vocabulary.errors[:phrases].first).to match(/at most 1000/)
    end
  end

  it 'queues a Mux sync when the phrases change' do
    vocabulary = create(:vocabulary)
    expect { vocabulary.update!(phrases: "DAC Sports\nDallas College") }.to change(SyncVocabularyJob.jobs, :size).by(1)
    expect { vocabulary.touch }.not_to change(SyncVocabularyJob.jobs, :size)
  end

  describe '#sync_to_mux!' do
    it 'creates the Mux vocabulary the first time and points captioned streams at it' do
      create(:channel, captions_enabled: true)
      Sidekiq::Worker.clear_all
      vocabulary = create(:vocabulary)
      allow(api).to receive(:create_transcription_vocabulary) do |request|
        expect(request.phrases).to include("DAC Sports", "Thunderducks")
        double(data: double(id: "MUXVOCAB"))
      end

      vocabulary.sync_to_mux!

      expect(vocabulary.reload).to have_attributes(mux_vocabulary_id: "MUXVOCAB", sync_error: nil)
      expect(SyncChannelCaptionsJob.jobs.size).to eq(1)
    end

    it 'updates the existing Mux vocabulary after that' do
      vocabulary = create(:vocabulary, mux_vocabulary_id: "MUXVOCAB")
      expect(api).to receive(:update_transcription_vocabulary).with("MUXVOCAB", anything)

      vocabulary.sync_to_mux!

      expect(SyncChannelCaptionsJob.jobs).to be_empty
    end

    it 'records a Mux failure for the admin page' do
      vocabulary = create(:vocabulary, mux_vocabulary_id: "MUXVOCAB")
      allow(api).to receive(:update_transcription_vocabulary).and_raise(MuxRuby::ApiError.new(message: "bad phrase"))

      expect { vocabulary.sync_to_mux! }.to raise_error(Vocabulary::SyncError)
      expect(vocabulary.reload.sync_error).to eq("bad phrase")
    end
  end
end
