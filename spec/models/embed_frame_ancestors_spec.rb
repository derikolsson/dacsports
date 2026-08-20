require 'rails_helper'

RSpec.describe EmbedFrameAncestors do
  after { Dacsports.redis.del(described_class::REDIS_KEY) }

  describe 'validation' do
    it 'accepts full origins, wildcards and ports' do
      %w[
        https://athletics.northlake.example.edu
        https://*.northlake.example.edu
        http://127.0.0.1:3198
        https://a.b.example.org
      ].each do |origin|
        expect(described_class.new(raw: origin)).to be_valid, "expected #{origin} to be accepted"
      end
    end

    it 'rejects a bare domain with no scheme' do
      expect(described_class.new(raw: "northlake.example.edu")).not_to be_valid
    end

    # The value is written verbatim into a response header, so a semicolon or newline
    # would let someone append their own CSP directives.
    it 'rejects attempts to inject extra CSP directives' do
      [
        "https://evil.org; default-src *",
        "https://evil.org\nscript-src *",
        "javascript:alert(1)",
        "*"
      ].each do |attempt|
        expect(described_class.new(raw: attempt)).not_to be_valid, "expected #{attempt.inspect} to be rejected"
      end
    end

    it 'rejects a port outside the valid range' do
      expect(described_class.new(raw: "https://a.org:443")).to be_valid
      expect(described_class.new(raw: "https://a.org:99999")).not_to be_valid
      expect(described_class.new(raw: "https://a.org:0")).not_to be_valid
    end

    it 'rejects a hostname longer than DNS allows, which would only bloat the header' do
      expect(described_class.new(raw: "https://#{'a' * 4000}.org")).not_to be_valid
    end

    it 'collapses duplicate entries' do
      settings = described_class.new(raw: "https://a.org\nhttps://a.org\nhttps://a.org")
      expect(settings.origins).to eq([ "https://a.org" ])
    end

    it 'rejects an unreasonable number of entries' do
      raw = Array.new(described_class::MAX_ORIGINS + 1) { |i| "https://site#{i}.example.org" }.join("\n")
      expect(described_class.new(raw: raw)).not_to be_valid
    end
  end

  describe '.header_value' do
    it "is 'none' when nothing is configured" do
      expect(described_class.header_value).to eq("'none'")
    end

    it 'lists the configured origins' do
      described_class.new(raw: "https://a.example.org\nhttps://b.example.org").save
      expect(described_class.header_value).to eq("https://a.example.org https://b.example.org")
    end
  end

  describe '#save' do
    it 'does not persist an invalid list' do
      described_class.new(raw: "https://good.example.org").save
      expect(described_class.new(raw: "https://evil.org; default-src *").save).to be false
      expect(described_class.header_value).to eq("https://good.example.org")
    end

    it 'clears the key when emptied, returning to blocked' do
      described_class.new(raw: "https://a.example.org").save
      described_class.new(raw: "").save
      expect(described_class.header_value).to eq("'none'")
    end
  end
end
