redis_host = ENV.fetch("REDIS_HOST", "localhost:6379")
REDIS = Redis.new(url: "redis://#{redis_host}/0")

# Set default timeout values if not already set
# These can be changed at runtime without redeployment
Dacsports.redis.set("keepalive_timeout", 60000, nx: true)
Dacsports.redis.set("event_status_ttl", 30000, nx: true)
