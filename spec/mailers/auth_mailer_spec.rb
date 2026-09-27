require 'rails_helper'

RSpec.describe AuthMailer, type: :mailer do
  let(:user) { create(:user, :pending, email_address: "invitee@example.com", invited_by: create(:user, name: "Dana")) }

  it "invites with a working link" do
    mail = AuthMailer.invitation(user)

    expect(mail.to).to eq([ "invitee@example.com" ])
    expect(mail.text_part.body.to_s).to include("Dana invited you")
    token = mail.text_part.body.to_s[%r{/internal/invitations/(\S+)}, 1]
    expect(User.find_by_token_for(:invitation, token)).to eq(user)
  end
end
