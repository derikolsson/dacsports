FactoryBot.define do
  factory :event do
    sequence(:title) { |n| "Basketball Game #{n}" }
    sequence(:slug) { |n| "basketball-game-#{n}" }
    sport { "Men's Volleyball" }
    location { "Main Arena" }
    round { nil }
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

    trait :technical_difficulties do
      status { :technical_difficulties }
      start_at { 1.hour.ago }
      live_embed_code { "<iframe src='https://example.com/live'></iframe>" }
    end

    trait :replay_available do
      status { :replay_available }
      start_at { 1.week.ago }
      replay_embed_code { "<iframe src='https://example.com/replay'></iframe>" }
    end

    # Signed playback IDs, used by the embed route. Distinct from the public ones.
    trait :signed_live do
      status { :live }
      start_at { 1.hour.ago }
      live_embed_code { nil }
      mux_live_signed_playback_id { "SIGNEDLIVEPLAYBACKID" }
    end

    trait :signed_replay do
      status { :replay_available }
      start_at { 1.week.ago }
      replay_embed_code { nil }
      mux_replay_signed_playback_id { "SIGNEDREPLAYPLAYBACKID" }
    end

    trait :hidden do
      visible { false }
    end

    trait :quarterfinal do
      round { "Quarterfinal" }
    end

    trait :semifinal do
      round { "Semifinal" }
    end

    trait :championship do
      round { "Championship" }
    end
  end
end
