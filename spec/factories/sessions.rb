FactoryBot.define do
  factory :session do
    visitor_id { SecureRandom.uuid }
    last_seen_at { Time.current }
    user_agent { "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36" }
    browser_name { "Chrome" }
    os_name { "Mac" }
    device_type { "desktop" }

    trait :active do
      last_seen_at { 1.minute.ago }
    end

    trait :inactive do
      last_seen_at { 10.minutes.ago }
    end
  end
end
