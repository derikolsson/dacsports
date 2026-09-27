# A signed-in browser. Not to be confused with Session, which tracks anonymous viewers.
class UserSession < ApplicationRecord
  LIFETIME = 30.days

  belongs_to :user

  scope :unexpired, -> { where(created_at: LIFETIME.ago..) }

  # The session behind a signed cookie, provided it hasn't expired and its user can still sign in.
  def self.resume(id)
    return if id.blank?

    user_session = unexpired.includes(:user).find_by(id: id)
    user_session if user_session&.user&.active?
  end
end
