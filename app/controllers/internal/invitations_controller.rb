class Internal::InvitationsController < Internal::ApplicationController
  allow_unauthenticated_access
  before_action :set_user

  layout "internal_auth"

  def show
  end

  def update
    if @user.accept_invitation(**params.require(:user).permit(:name, :password, :password_confirmation).to_h.symbolize_keys)
      sign_in(@user)
      redirect_to edit_internal_account_path, notice: "Welcome aboard! Add a passkey below to sign in with Face ID, Touch ID, or your phone next time."
    else
      render :show, status: :unprocessable_content
    end
  end

  private

  def set_user
    @user = User.find_by_token_for(:invitation, params[:token])
    return if @user&.pending?

    redirect_to internal_login_path, alert: "That invitation link has expired or was already used. Ask an admin to send a new one."
  end
end
