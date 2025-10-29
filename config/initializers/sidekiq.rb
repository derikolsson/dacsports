require "sidekiq/web"

Sidekiq.configure_server do |config|
  redis_host = ENV.fetch("REDIS_HOST", "localhost:6379")
  config.redis = { url: "redis://#{redis_host}/1" }
end

Sidekiq.configure_client do |config|
  redis_host = ENV.fetch("REDIS_HOST", "localhost:6379")
  config.redis = { url: "redis://#{redis_host}/1" }
end

# Load sidekiq-cron schedule
schedule_file = "config/schedule.yml"
if File.exist?(schedule_file) && Sidekiq.server?
  Sidekiq::Cron::Job.load_from_hash YAML.load_file(schedule_file)
end

# Mount Sidekiq Web UI with HTTP Basic Auth (configured in routes.rb)
Sidekiq::Web.use Rack::Auth::Basic do |username, password|
  ActiveSupport::SecurityUtils.secure_compare(
    username,
    Rails.application.credentials.dig(:internal_auth, :username) || "admin"
  ) &
  ActiveSupport::SecurityUtils.secure_compare(
    password,
    Rails.application.credentials.dig(:internal_auth, :password) || "changeme"
  )
end
