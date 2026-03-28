class Event < ApplicationRecord
  # Associations
  has_many :event_visits, dependent: :destroy
  has_many :event_slugs, dependent: :destroy
  has_many :event_teams, dependent: :destroy
  has_many :teams, through: :event_teams
  accepts_nested_attributes_for :event_teams, allow_destroy: true, reject_if: proc { |attrs| attrs["team_id"].blank? }

  # Available sports
  SPORTS = [
    "Men's Soccer",
    "Women's Soccer",
    "Men's Volleyball",
    "Women's Volleyball",
    "Men's Basketball",
    "Women's Basketball",
    "Men's Football",
    "Women's Football",
    "Baseball"
  ].freeze

  # Enum for status
  enum :status, {
    upcoming: "upcoming",
    live: "live",
    ended: "ended",
    replay_pending: "replay_pending",
    replay_available: "replay_available",
    technical_difficulties: "technical_difficulties"
  }, default: :upcoming

  # Validations
  validates :title, :start_at, :time_zone, presence: true
  validate :live_video_source_present, if: -> { live? }
  validate :replay_video_source_present, if: -> { replay_available? }
  validates :sport, inclusion: { in: SPORTS, allow_blank: true }
  validates :slug, presence: true, uniqueness: true

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
    return "" if sport.blank?

    sport_lower = sport.downcase

    if sport_lower.include?("soccer")
      "⚽"
    elsif sport_lower.include?("volleyball")
      "🏐"
    elsif sport_lower.include?("basketball")
      "🏀"
    elsif sport_lower.include?("football")
      "🏈"
    elsif sport_lower.include?("baseball")
      "⚾"
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
    upcoming? && has_live_video_source?
  end

  def can_end?
    live? || technical_difficulties?
  end

  def can_mark_replay_pending?
    live? || technical_difficulties?
  end

  def can_mark_technical_difficulties?
    live?
  end

  def can_publish_replay?
    (replay_pending? || technical_difficulties?) && has_replay_video_source?
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

  def mark_technical_difficulties!
    return false unless can_mark_technical_difficulties?
    update!(status: :technical_difficulties)
  end

  def publish_replay!
    return false unless can_publish_replay?
    update!(status: :replay_available)
  end

  # Related events - same sport within +/- 3 days
  def related_events
    return Event.none if sport.blank? || start_at.blank?

    Event.visible
         .where(sport: sport)
         .where.not(id: id)
         .where("start_at BETWEEN ? AND ?",
                start_at - 3.days,
                start_at + 3.days)
         .order(:start_at)
  end

  # Cache busting
  before_save :bump_force_reload_count

  # Slug history tracking
  before_update :archive_slug_if_changed

  private

  def bump_force_reload_count
    if title_changed? || live_embed_code_changed? || replay_embed_code_changed? ||
       mux_live_playback_id_changed? || mux_replay_playback_id_changed? || status_changed?
      self.force_reload_count += 1
    end
  end

  def has_live_video_source?
    live_embed_code.present? || mux_live_playback_id.present?
  end

  def has_replay_video_source?
    replay_embed_code.present? || mux_replay_playback_id.present?
  end

  def live_video_source_present
    unless has_live_video_source?
      errors.add(:base, "Live video source required (embed code or Mux playback ID)")
    end
  end

  def replay_video_source_present
    unless has_replay_video_source?
      errors.add(:base, "Replay video source required (embed code or Mux playback ID)")
    end
  end

  def archive_slug_if_changed
    if slug_changed?
      event_slugs.find_or_create_by(slug: slug_was)
    end
  end
end
