# Signed-in staff for /internal. Modeled on the Rails 8 authentication generator,
# but named UserSession because Session already tracks anonymous viewers.
module Authentication
  extend ActiveSupport::Concern

  COOKIE = :user_session_id

  included do
    before_action :require_authentication
    helper_method :authenticated?, :current_user
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private

  def authenticated?
    resume_session.present?
  end

  def current_user
    Current.user
  end

  def require_authentication
    resume_session || request_authentication
  end

  def resume_session
    Current.user_session ||= UserSession.resume(cookies.signed[COOKIE])
  end

  def request_authentication
    session[:return_to_after_authenticating] = request.url if request.get?
    redirect_to internal_login_path
  end

  # Starts a fresh session and returns where the user was headed before we asked them to sign in.
  def sign_in(user)
    return_to = session[:return_to_after_authenticating]
    reset_session

    user.update!(last_signed_in_at: Time.current)
    Current.user_session = user.user_sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip)
    cookies.signed[COOKIE] = {
      value: Current.user_session.id,
      expires: UserSession::LIFETIME.from_now,
      httponly: true,
      same_site: :lax,
      secure: Rails.env.production?
    }

    return_to || internal_root_url
  end

  def sign_out
    Current.user_session&.destroy
    Current.user_session = nil
    cookies.delete(COOKIE)
  end
end
