# Sign in by emailed link. Opening the link shows a button rather than signing straight in,
# so mail scanners that prefetch links can't use it up.
class Internal::MagicLinksController < Internal::ApplicationController
  allow_unauthenticated_access
  rate_limit to: 5, within: 3.minutes, only: :create,
    with: -> { redirect_to new_internal_magic_link_path, alert: "Too many requests. Try again in a few minutes." }
  before_action :set_user_by_token, only: [ :show, :update ]

  layout "internal_auth"

  def new
  end

  def create
    if (user = User.active.find_by(email_address: params[:email_address]))
      AuthMailer.magic_link(user).deliver_later
    end

    redirect_to internal_login_path, notice: "If that email has an account, we've sent it a sign-in link. It expires in 15 minutes."
  end

  def show
  end

  def update
    redirect_to sign_in(@user)
  end

  private

  def set_user_by_token
    @user = User.find_active_by_token_for(:magic_link, params[:token])
    return if @user

    redirect_to new_internal_magic_link_path, alert: "That sign-in link has expired or was already used. Request a new one."
  end
end
