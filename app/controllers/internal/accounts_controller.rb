class Internal::AccountsController < Internal::ApplicationController
  def edit
    @passkeys = current_user.passkeys.order(:created_at)
  end

  def update
    if params[:password_change]
      change_password
    elsif current_user.update(params.require(:user).permit(:name, :theme))
      redirect_to edit_internal_account_path, notice: "Saved."
    else
      render_edit
    end
  end

  private

  def change_password
    passwords = params.require(:user).permit(:current_password, :password, :password_confirmation)

    if !current_user.authenticate(passwords[:current_password])
      current_user.errors.add(:current_password, "is incorrect")
      render_edit
    elsif passwords[:password].blank?
      current_user.errors.add(:password, "can't be blank")
      render_edit
    elsif current_user.update(passwords.slice(:password, :password_confirmation))
      current_user.user_sessions.where.not(id: Current.user_session.id).destroy_all
      redirect_to edit_internal_account_path, notice: "Password changed. You've been signed out everywhere else."
    else
      render_edit
    end
  end

  def render_edit
    @passkeys = current_user.passkeys.order(:created_at)
    render :edit, status: :unprocessable_content
  end
end
