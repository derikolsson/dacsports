require 'rails_helper'
require 'webauthn/fake_client'

RSpec.describe "Passkeys", type: :request do
  let(:user) { create(:user) }
  let(:client) { WebAuthn::FakeClient.new(Rails.configuration.x.auth.origin) }

  def json_post(path, params = {}, headers = {})
    post path, params: params.to_json, headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }.merge(headers)
  end

  def register_passkey(authenticator: client)
    json_post options_internal_passkeys_path
    challenge = response.parsed_body["challenge"]
    json_post internal_passkeys_path, credential: authenticator.create(challenge: challenge).to_json
  end

  def sign_in_with_passkey(user_handle: user.webauthn_id)
    json_post options_internal_passkey_session_path
    challenge = response.parsed_body["challenge"]
    assertion = client.get(challenge: challenge, user_handle: WebAuthn.configuration.encoder.decode(user_handle))
    json_post internal_passkey_session_path, credential: assertion.to_json
  end

  it "registers a passkey named after the browser it was made in" do
    chrome_on_mac = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"
    sign_in_as user
    json_post options_internal_passkeys_path
    challenge = response.parsed_body["challenge"]
    json_post internal_passkeys_path, { credential: client.create(challenge: challenge).to_json }, { "User-Agent" => chrome_on_mac }

    expect(response).to have_http_status(:ok)
    expect(user.passkeys.sole.name).to eq("Chrome on Mac")
  end

  it "lets a user keep several passkeys, rename one and remove another" do
    sign_in_as user
    register_passkey
    register_passkey(authenticator: WebAuthn::FakeClient.new(Rails.configuration.x.auth.origin))
    first, second = user.passkeys.order(:id).to_a

    patch internal_passkey_path(first), params: { passkey: { name: "Work laptop" } }
    expect(first.reload.name).to eq("Work laptop")

    patch internal_passkey_path(first), params: { passkey: { name: "" } }
    expect(first.reload.name).to eq("Work laptop")

    delete internal_passkey_path(second)
    expect(user.passkeys.pluck(:name)).to eq([ "Work laptop" ])
  end

  it "won't rename someone else's passkey" do
    sign_in_as user
    register_passkey
    passkey = user.passkeys.sole

    delete internal_logout_path
    sign_in_as create(:user)
    patch internal_passkey_path(passkey), params: { passkey: { name: "Mine now" } }

    expect(response).to have_http_status(:not_found)
    expect(passkey.reload.name).not_to eq("Mine now")
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
