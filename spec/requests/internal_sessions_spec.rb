require 'rails_helper'

RSpec.describe "Internal::Sessions", type: :request do
  let(:user) { create(:user, email_address: "coach@example.com") }

  it "sends signed-out visitors to the login page, then back where they were headed" do
    get internal_events_path
    expect(response).to redirect_to(internal_login_path)

    post internal_login_path, params: { email_address: user.email_address, password: user.password }
    expect(response).to redirect_to(internal_events_url)
  end

  it "refuses a wrong password without saying which part was wrong" do
    post internal_login_path, params: { email_address: user.email_address, password: "wrong password" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("don&#39;t match")
    get internal_root_path
    expect(response).to redirect_to(internal_login_path)
  end

  it "refuses deactivated and pending users" do
    [ create(:user, :deactivated), create(:user, :pending) ].each do |blocked|
      post internal_login_path, params: { email_address: blocked.email_address, password: "correct horse battery" }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  it "signs out" do
    sign_in_as user
    delete internal_logout_path

    expect(response).to redirect_to(internal_login_path)
    expect(user.user_sessions.reload).to be_empty
    get internal_root_path
    expect(response).to redirect_to(internal_login_path)
  end

  it "ends the session when the user is deactivated" do
    sign_in_as user
    user.deactivate!

    get internal_root_path
    expect(response).to redirect_to(internal_login_path)
  end

  it "expires sessions after their lifetime" do
    sign_in_as user
    travel UserSession::LIFETIME + 1.minute do
      get internal_root_path
      expect(response).to redirect_to(internal_login_path)
    end
  end

  describe "admin-only areas" do
    it "keeps non-admins out of channels and Sidekiq" do
      sign_in_as user

      get internal_channels_path
      expect(response).to redirect_to(internal_root_path)

      get "/internal/sidekiq"
      expect(response).to redirect_to("/internal")

      post "/internal/sidekiq/queues/default", params: { delete: "Delete" }
      expect(response).to have_http_status(:not_found)
    end

    it "keeps signed-out visitors out of Sidekiq" do
      get "/internal/sidekiq/queues"
      expect(response).to redirect_to("/internal")

      post "/internal/sidekiq/queues/default", params: { delete: "Delete" }
      expect(response).to have_http_status(:not_found)
    end

    it "lets admins into Sidekiq" do
      sign_in_as create(:user, :admin)
      get "/internal/sidekiq"
      expect(response).to have_http_status(:ok)
    end
  end

  it "leaves the public site alone" do
    get root_path
    expect(response).to have_http_status(:ok)
  end
end
