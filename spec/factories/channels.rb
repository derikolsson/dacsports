FactoryBot.define do
  factory :channel do
    sequence(:name) { |n| "Channel #{n}" }
    sequence(:mux_live_stream_id) { |n| "LIVESTREAM#{n}" }
    mux_live_playback_id { "PUBLICLIVEPLAYBACKID" }
    mux_live_signed_playback_id { "SIGNEDLIVEPLAYBACKID" }
  end
end
