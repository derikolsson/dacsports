require 'rails_helper'

RSpec.describe EventPoster do
  let(:client) { Aws::S3::Client.new(stub_responses: true) }

  before do
    allow(described_class).to receive(:config).and_return(bucket: "posters", region: "us-east-1")
    allow(Aws::S3::Client).to receive(:new).and_return(client)
  end

  describe '.upload' do
    it 'puts the image under a fresh key with its type and a long cache life' do
      key = described_class.upload(StringIO.new("png"), content_type: "image/png")

      expect(key).to match(%r{\Aevents/[0-9a-f-]{36}\.png\z})
      request = client.api_requests.last
      expect(request[:operation_name]).to eq(:put_object)
      expect(request[:params]).to include(bucket: "posters", key: key, content_type: "image/png",
                                          cache_control: "public, max-age=31536000, immutable")
    end

    it 'gives each upload its own key' do
      keys = 2.times.map { described_class.upload(StringIO.new("x"), content_type: "image/jpeg") }

      expect(keys.uniq.size).to eq(2)
    end

    it 'wraps S3 failures' do
      client.stub_responses(:put_object, "AccessDenied")

      expect { described_class.upload(StringIO.new("x"), content_type: "image/png") }
        .to raise_error(EventPoster::Error)
    end
  end

  describe '.url' do
    it 'points at the bucket by default' do
      expect(described_class.url("events/a.png")).to eq("https://posters.s3.us-east-1.amazonaws.com/events/a.png")
    end

    it 'uses the configured host when there is one' do
      allow(described_class).to receive(:config).and_return(bucket: "posters", host: "https://cdn.example.com/")

      expect(described_class.url("events/a.png")).to eq("https://cdn.example.com/events/a.png")
    end

    it 'is nil without a key' do
      expect(described_class.url(nil)).to be_nil
    end
  end
end
