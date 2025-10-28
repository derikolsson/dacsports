class Internal::ApplicationController < ActionController::Base
  http_basic_authenticate_with(
    name: Rails.application.credentials.dig(:internal_auth, :username),
    password: Rails.application.credentials.dig(:internal_auth, :password)
  )

  layout "internal"
end
