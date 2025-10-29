redis_host = ENV.fetch("REDIS_HOST", "localhost:6379")
REDIS = Redis.new(url: "redis://#{redis_host}/0")

# Set default timeout values if not already set
# These can be changed at runtime without redeployment
# Skip during asset precompilation when Redis may not be available
unless defined?(Rails::Console) || File.basename($0) == "rake" && ARGV.include?("assets:precompile")
  begin
    Dacsports.redis.set("keepalive_timeout", 60000, nx: true)
    Dacsports.redis.set("event_status_ttl", 30000, nx: true)
  rescue Redis::CannotConnectError, Errno::ECONNREFUSED => e
    Rails.logger.warn "Redis not available during initialization: #{e.message}" if defined?(Rails.logger)
  end
end
