class Internal::UsersController < Internal::ApplicationController
  before_action :require_admin
  before_action :set_user, only: [ :update, :destroy, :resend_invitation, :reactivate ]
  before_action :refuse_self, only: [ :update, :destroy ]

  def index
    users = User.includes(:invited_by).order(:email_address)
    @active_users = users.select(&:active?)
    @pending_users = users.select(&:pending?)
    @deactivated_users = users.select(&:deactivated?)
  end

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params.merge(invited_by: current_user, admin: params.require(:user)[:admin] == "1"))
    if @user.save
      AuthMailer.invitation(@user).deliver_later
      redirect_to internal_users_path, notice: "Invitation sent to #{@user.email_address}."
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    @user.update!(admin: params.require(:user)[:admin] == "1")
    redirect_to internal_users_path, notice: "#{@user.display_name} is #{@user.admin? ? "now an admin" : "no longer an admin"}."
  end

  def destroy
    if @user.pending?
      @user.destroy!
      redirect_to internal_users_path, notice: "Invitation for #{@user.email_address} revoked."
    else
      @user.deactivate!
      redirect_to internal_users_path, notice: "#{@user.display_name} can no longer sign in."
    end
  end

  def resend_invitation
    if @user.pending?
      AuthMailer.invitation(@user).deliver_later
      redirect_to internal_users_path, notice: "Invitation re-sent to #{@user.email_address}."
    else
      redirect_to internal_users_path, alert: "#{@user.email_address} has already accepted."
    end
  end

  def reactivate
    @user.update!(deactivated_at: nil)
    AuthMailer.invitation(@user).deliver_later if @user.pending?
    redirect_to internal_users_path, notice: "#{@user.display_name} can sign in again."
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def refuse_self
    redirect_to internal_users_path, alert: "Ask another admin to change your own access." if @user == current_user
  end

  def user_params
    params.require(:user).permit(:email_address, :name)
  end
end
