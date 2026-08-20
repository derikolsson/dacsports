class EventVisit < ApplicationRecord
  # The two states worth counting a view in. Other statuses have no player on screen.
  TRACKED_STATUSES = %w[live vod].freeze

  # Where the view came from. "dsn" is DAC Sports Network's own site; embed views carry
  # "embed:<origin>" so partner traffic stays separable per property.
  DEFAULT_SOURCE = "dsn".freeze

  belongs_to :session
  belongs_to :event

  validates :event_status, presence: true, inclusion: { in: TRACKED_STATUSES }
  validates :source, presence: true

  scope :on_site, -> { where(source: DEFAULT_SOURCE) }
  scope :embedded, -> { where.not(source: DEFAULT_SOURCE) }

  def embedded?
    source != DEFAULT_SOURCE
  end
end
