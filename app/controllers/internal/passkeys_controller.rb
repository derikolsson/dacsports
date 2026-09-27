# Adding, renaming and removing passkeys for the signed-in user. The browser half lives in app/javascript/passkeys.js.
class Internal::PasskeysController < Internal::ApplicationController
  CHALLENGE = :passkey_registration_challenge

  def options
    options = WebAuthn::Credential.options_for_create(
      user: { id: current_user.webauthn_id, name: current_user.email_address, display_name: current_user.display_name },
      exclude: current_user.passkeys.pluck(:external_id),
      authenticator_selection: { resident_key: "required", user_verification: "preferred" }
    )
    session[CHALLENGE] = options.challenge
    render json: options
  end

  def create
    challenge = session.delete(CHALLENGE)
    credential = WebAuthn::Credential.from_create(JSON.parse(params.require(:credential)))
    credential.verify(challenge, user_verification: false)

    current_user.passkeys.create!(
      external_id: credential.id,
      public_key: credential.public_key,
      sign_count: credential.sign_count,
      name: default_name
    )
    flash[:notice] = "Passkey added. Next time, choose “Sign in with a passkey.”"
    render json: { redirect_to: edit_internal_account_path }
  rescue WebAuthn::Error, JSON::ParserError, TypeError, ActiveRecord::RecordInvalid => e
    Rails.logger.info("Passkey registration failed for user #{current_user.id}: #{e.class}: #{e.message}")
    render json: { error: "That passkey couldn't be added. Please try again." }, status: :unprocessable_content
  end

  def update
    passkey = current_user.passkeys.find(params[:id])
    if passkey.update(params.require(:passkey).permit(:name))
      redirect_to edit_internal_account_path, notice: "Passkey renamed."
    else
      redirect_to edit_internal_account_path, alert: "A passkey needs a name."
    end
  end

  def destroy
    passkey = current_user.passkeys.find(params[:id])
    passkey.destroy!
    redirect_to edit_internal_account_path, notice: "Removed “#{passkey.name}.”"
  end

  private

  def default_name
    device = DeviceDetector.new(request.user_agent)
    [ device.name, device.os_name ].compact.join(" on ").presence || "Passkey"
  end
end
