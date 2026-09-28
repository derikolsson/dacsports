module SessionManagement
  extend ActiveSupport::Concern

  included do
    before_action :set_current_session
  end

  private

  def set_current_session
    visitor_id = get_or_create_visitor_id

    # Find most recent session for this visitor
    user_session = Session.where(visitor_id: visitor_id)
                          .order(last_seen_at: :desc)
                          .first

    # If no session exists or the session is expired (> 10 minutes inactive),
    # create a new session
    if user_session.nil? || !user_session.active?
      user_session = Session.create!(
        visitor_id: visitor_id,
        user_agent: request.user_agent,
        last_seen_at: Time.current,
        **session_arrival
      )
      user_session.parse_user_agent! if user_session.user_agent.present?
    else
      # Session is active, just update last_seen_at
      user_session.update_column(:last_seen_at, Time.current)
    end

    Current.session = user_session
    Current.request_id = request.uuid
    Current.ip_address = request.ip
  end

  # Where a new session came from: the referring site (never our own), the page it
  # landed on, and any UTM tags. Overridden where the request isn't a real arrival.
  def session_arrival
    referrer_host = URI.parse(request.referer.to_s).host if request.referer.present?

    {
      landing_referrer_host: (referrer_host unless referrer_host == request.host),
      landing_path: request.path,
      utm_source: params[:utm_source],
      utm_medium: params[:utm_medium],
      utm_campaign: params[:utm_campaign]
    }.transform_values { |value| value.presence&.to_s&.truncate(255) }
  rescue URI::InvalidURIError
    {}
  end

  def get_or_create_visitor_id
    # Check for existing visitor_id cookie
    return cookies[:visitor_id] if cookies[:visitor_id].present?

    # Generate new visitor_id and store in permanent cookie
    cookies.permanent[:visitor_id] = SecureRandom.uuid
  end
end
