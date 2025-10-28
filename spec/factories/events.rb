FactoryBot.define do
  factory :event do
    title { "Basketball Game" }
    sequence(:slug) { |n| "event-slug-#{n}" }
    subtitle { "Championship Finals" }
    event_date { 1.week.from_now.to_date }
    start_at { 1.week.from_now }
    time_zone { "America/Chicago" }
    status { :upcoming }
    visible { true }
    force_reload_count { 0 }
    description { "An exciting game" }

    trait :upcoming do
      status { :upcoming }
    end

    trait :live do
      status { :live }
      start_at { 1.hour.ago }
      event_date { Date.current }
      live_embed_code { "<iframe src='https://example.com/live'></iframe>" }
    end

    trait :ended do
      status { :ended }
      start_at { 1.week.ago }
      event_date { 1.week.ago.to_date }
    end

    trait :replay_pending do
      status { :replay_pending }
      start_at { 1.week.ago }
      event_date { 1.week.ago.to_date }
    end

    trait :replay_available do
      status { :replay_available }
      start_at { 1.week.ago }
      event_date { 1.week.ago.to_date }
      replay_embed_code { "<iframe src='https://example.com/replay'></iframe>" }
    end

    trait :hidden do
      visible { false }
    end
  end
end
