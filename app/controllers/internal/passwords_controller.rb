class Internal::PasswordsController < Internal::ApplicationController
  allow_unauthenticated_access
  rate_limit to: 5, within: 3.minutes, only: :create,
    with: -> { redirect_to new_internal_password_path, alert: "Too many requests. Try again in a few minutes." }
  before_action :set_user_by_token, only: [ :edit, :update ]

  layout "internal_auth"

  def new
  end

  def create
    if (user = User.active.find_by(email_address: params[:email_address]))
      AuthMailer.password_reset(user).deliver_later
    end

    redirect_to internal_login_path, notice: "If that email has an account, we've sent it a link to reset the password."
  end

  def edit
  end

  def update
    passwords = params.permit(:password, :password_confirmation)

    if passwords[:password].blank?
      @user.errors.add(:password, "can't be blank")
      render :edit, status: :unprocessable_content
    elsif @user.update(passwords)
      @user.user_sessions.destroy_all
      redirect_to internal_login_path, notice: "Password reset. Sign in with your new password."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def set_user_by_token
    @user = User.find_by_password_reset_token(params[:token])
    return if @user&.active?

    redirect_to new_internal_password_path, alert: "That reset link has expired or was already used. Request a new one."
  end
end
