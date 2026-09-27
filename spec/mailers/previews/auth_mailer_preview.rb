# Preview at /rails/mailers/auth_mailer
class AuthMailerPreview < ActionMailer::Preview
  def invitation
    AuthMailer.invitation(User.pending.first || User.new(email_address: "invitee@example.com", invited_by: User.first))
  end
end
