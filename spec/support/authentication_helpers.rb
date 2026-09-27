module AuthenticationHelpers
  def sign_in_as(user)
    post internal_login_path, params: { email_address: user.email_address, password: user.password }
    raise "sign in failed for #{user.email_address}" unless response.redirect?
    user
  end
end

RSpec.configure do |config|
  config.include AuthenticationHelpers, type: :request
  config.include ActiveSupport::Testing::TimeHelpers, type: :request
end
