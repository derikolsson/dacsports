# Route constraint for mounted apps (Sidekiq) that sit outside our controllers.
class AdminConstraint
  def self.matches?(request)
    UserSession.resume(request.cookie_jar.signed[Authentication::COOKIE])&.user&.admin?
  end
end
