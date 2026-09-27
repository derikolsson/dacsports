require 'rails_helper'

RSpec.describe "Internal::Passwords", type: :request do
  let(:user) { create(:user, email_address: "coach@example.com") }

  it "emails a reset link to known users without revealing who has an account" do
    user
    expect { post internal_passwords_path, params: { email_address: "coach@example.com" } }
      .to have_enqueued_mail(AuthMailer, :password_reset)
    expect { post internal_passwords_path, params: { email_address: "nobody@example.com" } }
      .not_to have_enqueued_mail
  end

  it "resets the password, signs out everywhere, and burns the link" do
    user.user_sessions.create!
    token = user.password_reset_token

    patch internal_password_path(token), params: { password: "a brand new password", password_confirmation: "a brand new password" }

    expect(response).to redirect_to(internal_login_path)
    expect(user.user_sessions.reload).to be_empty
    expect(User.authenticate(email_address: user.email_address, password: "a brand new password")).to eq(user)

    get edit_internal_password_path(token)
    expect(response).to redirect_to(new_internal_password_path)
  end

  it "won't accept a blank password" do
    patch internal_password_path(user.password_reset_token), params: { password: "", password_confirmation: "" }
    expect(response).to have_http_status(:unprocessable_content)
  end
end
