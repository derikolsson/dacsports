MuxRuby.configure do |config|
  config.username = Rails.application.credentials.dig(:mux, :token_id)
  config.password = Rails.application.credentials.dig(:mux, :token_secret)
end
