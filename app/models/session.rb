class Session < ApplicationRecord
  has_many :event_visits, dependent: :destroy

  validates :visitor_id, presence: true

  def active?
    last_seen_at && last_seen_at > 3.minutes.ago
  end

  def parse_user_agent!
    return if user_agent.blank?

    detector = DeviceDetector.new(user_agent)
    self.browser_name = detector.name
    self.os_name = detector.os_name
    self.device_type = detector.device_type
    save!
  end
end
