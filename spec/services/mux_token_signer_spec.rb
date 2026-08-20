require 'rails_helper'

RSpec.describe MuxTokenSigner do
  before { stub_mux_signing_credentials }

  let(:playback_id) { "SOMEPLAYBACKID" }
  let(:restriction) { "TESTRESTRICTIONA" }
  let(:signer) { described_class.new(playback_restriction_id: restriction) }

  describe '#sign' do
    it 'signs with RS256 and puts the key id in the header' do
      _payload, header = decode_mux_token(signer.sign(playback_id, "v")).then { |p, h| [ p, h ] }

      expect(header["alg"]).to eq("RS256")
      expect(header["kid"]).to eq(MuxSigningHelpers::TEST_KEY_ID)
    end

    it 'puts the playback id in sub and the key id in the claims' do
      payload, = decode_mux_token(signer.sign(playback_id, "v"))

      expect(payload["sub"]).to eq(playback_id)
      expect(payload["kid"]).to eq(MuxSigningHelpers::TEST_KEY_ID)
    end

    it 'sets the requested audience' do
      %w[v t s].each do |aud|
        payload, = decode_mux_token(signer.sign(playback_id, aud))
        expect(payload["aud"]).to eq(aud)
      end
    end

    it 'includes the playback restriction id' do
      payload, = decode_mux_token(signer.sign(playback_id, "v"))
      expect(payload["playback_restriction_id"]).to eq(restriction)
    end

    it 'omits the restriction claim when none is given' do
      payload, = decode_mux_token(described_class.new.sign(playback_id, "v"))
      expect(payload).not_to have_key("playback_restriction_id")
    end

    # Mux cannot rotate a token without tearing down playback, and disconnects
    # continuous streams at ~12h, so the token must outlast any stream that can exist.
    it 'expires in 12 hours by default' do
      payload, = decode_mux_token(signer.sign(playback_id, "v"))
      expect(payload["exp"]).to be_within(60).of(12.hours.from_now.to_i)
    end

    it 'requires a playback id' do
      expect { signer.sign(nil, "v") }.to raise_error(ArgumentError)
    end

    # This is what lets one signed playback ID serve both the partner embeds and, later,
    # our own pages — only the restriction claim differs.
    it 'produces valid tokens for the same playback id under different restrictions' do
      a, = decode_mux_token(described_class.new(playback_restriction_id: "A").sign(playback_id, "v"))
      b, = decode_mux_token(described_class.new(playback_restriction_id: "B").sign(playback_id, "v"))

      expect(a["playback_restriction_id"]).to eq("A")
      expect(b["playback_restriction_id"]).to eq("B")
      expect(a.except("playback_restriction_id", "exp")).to eq(b.except("playback_restriction_id", "exp"))
    end
  end

  describe '#tokens_for' do
    it 'returns all three tokens for on-demand' do
      tokens = signer.tokens_for(playback_id, live: false)

      expect(tokens[:playback]).to be_present
      expect(tokens[:thumbnail]).to be_present
      expect(tokens[:storyboard]).to be_present
    end

    # Mux only generates storyboards for on-demand assets.
    it 'omits the storyboard token for live' do
      tokens = signer.tokens_for(playback_id, live: true)

      expect(tokens[:playback]).to be_present
      expect(tokens[:thumbnail]).to be_present
      expect(tokens[:storyboard]).to be_nil
    end

    it 'scopes each token to its own resource' do
      tokens = signer.tokens_for(playback_id, live: false)

      expect(decode_mux_token(tokens[:playback]).first["aud"]).to eq("v")
      expect(decode_mux_token(tokens[:thumbnail]).first["aud"]).to eq("t")
      expect(decode_mux_token(tokens[:storyboard]).first["aud"]).to eq("s")
    end
  end

  describe '.configured?' do
    it 'is true when both key parts are present' do
      expect(described_class).to be_configured
    end

    it 'is false when the key is missing' do
      allow(described_class).to receive(:credentials).and_return({})
      expect(described_class).not_to be_configured
    end
  end
end
