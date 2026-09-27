class Internal::SessionsController < Internal::ApplicationController
  allow_unauthenticated_access only: [ :new, :create ]
  rate_limit to: 10, within: 3.minutes, only: :create,
    with: -> { redirect_to internal_login_path, alert: "Too many attempts. Try again in a few minutes." }

  layout "internal_auth"

  def new
    redirect_to internal_root_path if authenticated?
  end

  def create
    if (user = User.authenticate(email_address: params[:email_address], password: params[:password]))
      redirect_to sign_in(user)
    else
      flash.now[:alert] = "That email and password don't match."
      render :new, status: :unprocessable_content
    end
  end

  def destroy
    sign_out
    redirect_to internal_login_path, notice: "You're signed out."
  end
end
