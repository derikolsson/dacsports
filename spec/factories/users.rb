FactoryBot.define do
  factory :user do
    sequence(:email_address) { |n| "user#{n}@example.com" }
    name { "Staff Member" }
    password { "correct horse battery" }
    invitation_accepted_at { 1.day.ago }

    trait :admin do
      admin { true }
    end

    trait :pending do
      password { nil }
      invitation_accepted_at { nil }
    end

    trait :deactivated do
      deactivated_at { 1.hour.ago }
    end
  end
end
