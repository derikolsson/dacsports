FactoryBot.define do
  factory :event_slug do
    association :event
    sequence(:slug) { |n| "archived-event-slug-#{n}" }

    trait :from_title_change do
      slug { "old-game-title" }
    end

    trait :from_team_change do
      slug { "team-a-vs-team-b" }
    end

    trait :from_date_change do
      slug { "championship-2024-01-15" }
    end
  end
end
