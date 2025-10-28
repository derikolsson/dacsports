FactoryBot.define do
  factory :event do
    sequence(:title) { |n| "Basketball Game #{n}" }
    subtitle { "Championship Finals" }
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
      live_embed_code { "<iframe src='https://example.com/live'></iframe>" }
    end

    trait :ended do
      status { :ended }
      start_at { 1.week.ago }
    end

    trait :replay_pending do
      status { :replay_pending }
      start_at { 1.week.ago }
    end

    trait :replay_available do
      status { :replay_available }
      start_at { 1.week.ago }
      replay_embed_code { "<iframe src='https://example.com/replay'></iframe>" }
    end

    trait :hidden do
      visible { false }
    end
  end
end
