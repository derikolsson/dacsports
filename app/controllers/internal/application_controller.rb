class Internal::ApplicationController < ActionController::Base
  include Authentication

  layout "internal"

  private

  def require_admin
    redirect_to internal_root_path, alert: "Only admins can do that." unless current_user.admin?
  end
end
