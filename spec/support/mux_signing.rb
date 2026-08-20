# A throwaway RSA key so signing specs never touch real credentials.
module MuxSigningHelpers
  TEST_KEY_ID = "test-signing-key-id".freeze

  def self.private_key
    @private_key ||= OpenSSL::PKey::RSA.generate(2048)
  end

  def stub_mux_signing_credentials
    allow(MuxTokenSigner).to receive(:credentials).and_return(
      signing_key_id: MuxSigningHelpers::TEST_KEY_ID,
      signing_key_private: Base64.strict_encode64(MuxSigningHelpers.private_key.to_pem),
      playback_restriction_id_embed: "TESTRESTRICTIONA"
    )
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig)
      .with(:mux, :playback_restriction_id_embed).and_return("TESTRESTRICTIONA")
  end

  def decode_mux_token(token)
    JWT.decode(token, MuxSigningHelpers.private_key.public_key, true, algorithm: "RS256")
  end
end

RSpec.configure do |config|
  config.include MuxSigningHelpers
end
