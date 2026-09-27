class Internal::ApplicationController < ActionController::Base
  include Authentication

  # Passkeys are bound to one domain, so staff always use the canonical host.
  prepend_before_action :redirect_to_canonical_host

  layout "internal"

  private

  def require_admin
    redirect_to internal_root_path, alert: "Only admins can do that." unless current_user.admin?
  end

  def redirect_to_canonical_host
    host = Rails.configuration.x.auth.host
    return unless Rails.env.production? && request.get? && request.host != host

    redirect_to request.url.sub(request.host, host), allow_other_host: true, status: :moved_permanently
  end
end
