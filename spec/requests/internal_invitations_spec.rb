require 'rails_helper'

RSpec.describe "Internal::Invitations", type: :request do
  let(:user) { create(:user, :pending, email_address: "invitee@example.com") }
  let(:token) { user.generate_token_for(:invitation) }
  let(:valid_params) { { user: { name: "Pat", password: "a long enough password", password_confirmation: "a long enough password" } } }

  it "shows the setup form" do
    get internal_invitation_path(token)
    expect(response.body).to include("invitee@example.com")
  end

  it "sets up the account and signs the user in" do
    patch internal_invitation_path(token), params: valid_params

    expect(response).to redirect_to(edit_internal_account_path)
    expect(user.reload).to be_active
    expect(user.name).to eq("Pat")
    get internal_root_path
    expect(response).to have_http_status(:ok)
  end

  it "rejects a short password" do
    patch internal_invitation_path(token), params: { user: { name: "Pat", password: "short", password_confirmation: "short" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(user.reload).to be_pending
  end

  it "can't be used twice" do
    patch internal_invitation_path(token), params: valid_params
    delete internal_logout_path

    get internal_invitation_path(token)
    expect(response).to redirect_to(internal_login_path)
  end

  it "expires after 7 days" do
    token
    travel 8.days do
      get internal_invitation_path(token)
      expect(response).to redirect_to(internal_login_path)
    end
  end

  it "won't work once revoked" do
    token
    user.destroy!
    get internal_invitation_path(token)
    expect(response).to redirect_to(internal_login_path)
  end
end
