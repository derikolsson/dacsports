require 'rails_helper'

RSpec.describe "Internal::Users", type: :request do
  include ActiveJob::TestHelper

  let(:admin) { create(:user, :admin) }

  it "is admin-only" do
    sign_in_as create(:user)
    get internal_users_path
    expect(response).to redirect_to(internal_root_path)
  end

  describe "as an admin" do
    before { sign_in_as admin }

    it "lists active, pending and deactivated users" do
      create(:user, name: "Active Annie")
      create(:user, :pending, email_address: "pending@example.com")
      create(:user, :deactivated, name: "Gone Gary")

      get internal_users_path

      expect(response.body).to include("Active Annie", "pending@example.com", "Gone Gary")
    end

    it "invites someone by email" do
      perform_enqueued_jobs do
        post internal_users_path, params: { user: { email_address: "New@Example.com", admin: "0" } }
      end

      user = User.find_by(email_address: "new@example.com")
      expect(user).to be_pending
      expect(user.invited_by).to eq(admin)
      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to eq([ "new@example.com" ])
      expect(mail.body.encoded).to include("/internal/invitations/")
    end

    it "can invite another admin" do
      post internal_users_path, params: { user: { email_address: "boss@example.com", admin: "1" } }
      expect(User.find_by(email_address: "boss@example.com")).to be_admin
    end

    it "won't invite an existing email" do
      create(:user, email_address: "taken@example.com")
      post internal_users_path, params: { user: { email_address: "taken@example.com" } }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "promotes and demotes other users, but not themselves" do
      user = create(:user)
      patch internal_user_path(user), params: { user: { admin: "1" } }
      expect(user.reload).to be_admin

      patch internal_user_path(admin), params: { user: { admin: "0" } }
      expect(admin.reload).to be_admin
    end

    it "revokes pending invitations and deactivates accepted users" do
      pending_user = create(:user, :pending)
      active_user = create(:user)

      delete internal_user_path(pending_user)
      delete internal_user_path(active_user)

      expect(User.exists?(pending_user.id)).to be(false)
      expect(active_user.reload).to be_deactivated
    end

    it "reactivates a deactivated user" do
      user = create(:user, :deactivated)
      post reactivate_internal_user_path(user)
      expect(user.reload).to be_active
    end

    it "resends a pending invitation" do
      user = create(:user, :pending)
      expect { post resend_invitation_internal_user_path(user) }.to have_enqueued_mail(AuthMailer, :invitation)
    end
  end
end
