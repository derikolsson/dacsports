require 'rails_helper'
require 'webauthn/fake_client'

RSpec.describe "Passkeys", type: :request do
  let(:user) { create(:user) }
  let(:client) { WebAuthn::FakeClient.new(Rails.configuration.x.auth.origin) }

  def json_post(path, params = {})
    post path, params: params.to_json, headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
  end

  def register_passkey(name: "Work laptop", authenticator: client)
    json_post options_internal_passkeys_path
    challenge = response.parsed_body["challenge"]
    json_post internal_passkeys_path, credential: authenticator.create(challenge: challenge).to_json, name: name
  end

  def sign_in_with_passkey(user_handle: user.webauthn_id)
    json_post options_internal_passkey_session_path
    challenge = response.parsed_body["challenge"]
    assertion = client.get(challenge: challenge, user_handle: WebAuthn.configuration.encoder.decode(user_handle))
    json_post internal_passkey_session_path, credential: assertion.to_json
  end

  it "registers a passkey for the signed-in user" do
    sign_in_as user
    register_passkey

    expect(response).to have_http_status(:ok)
    expect(user.passkeys.sole).to have_attributes(name: "Work laptop")
  end

  it "lets a user keep several passkeys and remove one" do
    sign_in_as user
    register_passkey(name: "Laptop")
    register_passkey(name: "Phone", authenticator: WebAuthn::FakeClient.new(Rails.configuration.x.auth.origin))

    expect(user.passkeys.pluck(:name)).to contain_exactly("Laptop", "Phone")

    delete internal_passkey_path(user.passkeys.find_by(name: "Laptop"))
    expect(user.passkeys.pluck(:name)).to eq([ "Phone" ])
  end

  it "rejects a registration answering the wrong challenge" do
    sign_in_as user
    json_post options_internal_passkeys_path
    json_post internal_passkeys_path, credential: client.create(challenge: WebAuthn.configuration.encoder.encode("nope" * 8)).to_json

    expect(response).to have_http_status(:unprocessable_content)
    expect(user.passkeys).to be_empty
  end

  it "signs in with a registered passkey" do
    sign_in_as user
    register_passkey
    delete internal_logout_path

    sign_in_with_passkey

    expect(response.parsed_body["redirect_to"]).to eq(internal_root_url)
    expect(user.passkeys.sole.last_used_at).to be_present
    get internal_root_path
    expect(response).to have_http_status(:ok)
  end

  it "refuses a passkey whose user has been deactivated" do
    sign_in_as user
    register_passkey
    delete internal_logout_path
    user.deactivate!

    sign_in_with_passkey

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "refuses a passkey presented for a different user" do
    sign_in_as user
    register_passkey
    delete internal_logout_path

    sign_in_with_passkey(user_handle: create(:user).webauthn_id)

    expect(response).to have_http_status(:unprocessable_content)
  end
end
