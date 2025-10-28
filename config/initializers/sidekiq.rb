require "sidekiq/web"

Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1") }
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1") }
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
