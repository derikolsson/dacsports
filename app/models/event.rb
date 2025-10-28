class Event < ApplicationRecord
  # Friendly ID - simple slugged approach without history
  extend FriendlyId
  friendly_id :title, use: :slugged

  # Associations
  has_many :event_visits, dependent: :destroy

  # Available sports
  SPORTS = %w[Volleyball Soccer Basketball Football].freeze

  # Enum for status
  enum :status, {
    upcoming: "upcoming",
    live: "live",
    ended: "ended",
    replay_pending: "replay_pending",
    replay_available: "replay_available"
  }, default: :upcoming

  # Validations
  validates :title, :start_at, :time_zone, presence: true
  validates :live_embed_code, presence: true, if: -> { live? }
  validates :replay_embed_code, presence: true, if: -> { replay_available? }
  validates :sport, inclusion: { in: SPORTS, allow_blank: true }

  # Scopes
  scope :visible, -> { where(visible: true) }
  scope :upcoming_events, -> { upcoming.where("start_at >= ?", Time.current.beginning_of_day) }
  scope :past, -> { where(status: [ "ended", "replay_pending", "replay_available" ]) }
  scope :by_date, -> { order(start_at: :desc) }

  # Helper method for date display
  def event_date
    start_at&.in_time_zone(time_zone)&.to_date
  end

  # Sport emoji helper
  def sport_emoji
    case sport&.downcase
    when "soccer"
      "⚽"
    when "volleyball"
      "🏐"
    when "basketball"
      "🏀"
    when "football"
      "🏈"
    else
      ""
    end
  end

  # Display helpers
  def current_embed_code
    case status
    when "live"
      live_embed_code
    when "replay_available"
      replay_embed_code
    else
      nil
    end
  end

  def can_go_live?
    upcoming? && live_embed_code.present?
  end

  def can_end?
    live?
  end

  def can_mark_replay_pending?
    live?
  end

  def can_publish_replay?
    replay_pending? && replay_embed_code.present?
  end

  # State transitions
  def go_live!
    return false unless can_go_live?
    update!(status: :live)
  end

  def end_event!
    return false unless can_end?
    update!(status: :ended)
  end

  def mark_replay_pending!
    return false unless can_mark_replay_pending?
    update!(status: :replay_pending)
  end

  def publish_replay!
    return false unless can_publish_replay?
    update!(status: :replay_available)
  end

  # Cache busting
  before_save :bump_force_reload_count

  private

  def bump_force_reload_count
    if title_changed? || live_embed_code_changed? || replay_embed_code_changed? || status_changed?
      self.force_reload_count += 1
    end
  end
end
