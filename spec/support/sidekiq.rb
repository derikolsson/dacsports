require "sidekiq/testing"

# Jobs queue in memory instead of Redis; specs assert on what was enqueued.
Sidekiq::Testing.fake!

RSpec.configure do |config|
  config.before { Sidekiq::Worker.clear_all }
end
