FactoryBot.define do
  factory :event_visit do
    association :session
    association :event
    event_status { "live" }
    started_at { Time.current }
    last_seen_at { Time.current }

    trait :live do
      event_status { "live" }
    end

    trait :vod do
      event_status { "vod" }
    end

    trait :embedded do
      source { "embed:https://northlake.example.edu" }
      referrer_origin { "https://northlake.example.edu" }
    end
  end
end
