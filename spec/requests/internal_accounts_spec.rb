require 'rails_helper'

RSpec.describe "Internal::Accounts", type: :request do
  let(:user) { create(:user) }

  before { sign_in_as user }

  it "updates the name" do
    patch internal_account_path, params: { user: { name: "New Name" } }
    expect(user.reload.name).to eq("New Name")
  end

  it "saves the theme and renders pages in it" do
    get edit_internal_account_path
    expect(response.body).to include('name="user[theme]"')

    patch internal_account_path, params: { user: { theme: "dark" } }
    expect(user.reload.theme).to eq("dark")

    get internal_root_path
    expect(response.body).to include('data-theme-preference="dark"')
  end

  it "changes the password with the current one and signs out other browsers" do
    other_browser = user.user_sessions.create!

    patch internal_account_path, params: {
      password_change: "1",
      user: { current_password: "correct horse battery", password: "a brand new password", password_confirmation: "a brand new password" }
    }

    expect(response).to redirect_to(edit_internal_account_path)
    expect(UserSession.exists?(other_browser.id)).to be(false)
    get internal_root_path
    expect(response).to have_http_status(:ok)
  end

  it "refuses a password change without the current password" do
    patch internal_account_path, params: {
      password_change: "1",
      user: { current_password: "wrong", password: "a brand new password", password_confirmation: "a brand new password" }
    }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Current password is incorrect")
  end
end
