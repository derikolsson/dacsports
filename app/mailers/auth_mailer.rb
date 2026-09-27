class AuthMailer < ApplicationMailer
  def invitation(user)
    @user = user
    @inviter = user.invited_by
    @url = internal_invitation_url(user.generate_token_for(:invitation))
    mail to: user.email_address, subject: "You're invited to DAC Sports Network"
  end
end
