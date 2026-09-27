FactoryBot.define do
  factory :vocabulary do
    phrases { "DAC Sports" }

    trait :for_channel do
      channel
      phrases { "Main Court" }
    end
  end
end
