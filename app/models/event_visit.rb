class EventVisit < ApplicationRecord
  belongs_to :session
  belongs_to :event

  validates :event_status, presence: true, inclusion: { in: %w[live vod] }
end
