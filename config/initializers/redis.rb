redis_host = ENV.fetch("REDIS_HOST", "localhost:6379")
REDIS = Redis.new(url: "redis://#{redis_host}/0")
