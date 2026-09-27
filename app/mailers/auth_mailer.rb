class AuthMailer < ApplicationMailer
  def invitation(user)
    @user = user
    @inviter = user.invited_by
    @url = internal_invitation_url(user.generate_token_for(:invitation))
    mail to: user.email_address, subject: "You're invited to DAC Sports Network"
  end

  def magic_link(user)
    @user = user
    @url = internal_magic_link_url(user.generate_token_for(:magic_link))
    mail to: user.email_address, subject: "Your DAC Sports Network sign-in link"
  end

  def password_reset(user)
    @user = user
    @url = edit_internal_password_url(user.password_reset_token)
    mail to: user.email_address, subject: "Reset your DAC Sports Network password"
  end
end
