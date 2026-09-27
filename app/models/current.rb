class Current < ActiveSupport::CurrentAttributes
  # Viewer tracking (Session) and signed-in staff (UserSession) are separate.
  attribute :session, :user_session
  attribute :request_id, :ip_address

  delegate :user, to: :user_session, allow_nil: true
end
