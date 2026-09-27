# Passkey sign-in. Passkeys are discoverable, so the browser offers the user's passkeys without asking for an email.
class Internal::PasskeySessionsController < Internal::ApplicationController
  CHALLENGE = :passkey_authentication_challenge

  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :create,
    with: -> { render json: { error: "Too many attempts. Try again in a few minutes." }, status: :too_many_requests }

  def options
    options = WebAuthn::Credential.options_for_get(user_verification: "preferred")
    session[CHALLENGE] = options.challenge
    render json: options
  end

  def create
    challenge = session.delete(CHALLENGE)
    credential = WebAuthn::Credential.from_get(JSON.parse(params.require(:credential)))
    passkey = Passkey.includes(:user).find_by(external_id: credential.id)
    user = passkey&.user
    return refuse unless challenge && user&.active? && credential.user_handle == user.webauthn_id

    credential.verify(challenge, public_key: passkey.public_key, sign_count: passkey.sign_count, user_verification: false)
    passkey.update!(sign_count: credential.sign_count, last_used_at: Time.current)
    render json: { redirect_to: sign_in(user) }
  rescue WebAuthn::Error, JSON::ParserError, TypeError => e
    Rails.logger.info("Passkey sign-in failed: #{e.class}: #{e.message}")
    refuse
  end

  private

  def refuse
    render json: { error: "That passkey didn't work. Sign in with your password instead." }, status: :unprocessable_content
  end
end
