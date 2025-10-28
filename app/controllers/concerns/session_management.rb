module SessionManagement
  extend ActiveSupport::Concern

  included do
    before_action :set_current_session
  end

  private

  def set_current_session
    visitor_id = get_or_create_visitor_id

    user_session = Session.find_or_create_by(visitor_id: visitor_id) do |session|
      session.user_agent = request.user_agent
      session.last_seen_at = Time.current
    end

    # Parse user agent if not already parsed
    if user_session.browser_name.nil? && user_session.user_agent.present?
      user_session.parse_user_agent!
    end

    # Update last_seen_at
    user_session.update_column(:last_seen_at, Time.current)

    Current.session = user_session
    Current.request_id = request.uuid
    Current.ip_address = request.ip
  end

  def get_or_create_visitor_id
    # Check params (from client localStorage)
    return params[:visitor_id] if params[:visitor_id].present?

    # Check cookies
    return cookies[:visitor_id] if cookies[:visitor_id].present?

    # Generate new visitor_id
    new_visitor_id = SecureRandom.uuid
    cookies.permanent[:visitor_id] = new_visitor_id
    new_visitor_id
  end
end
