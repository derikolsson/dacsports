class EventSlug < ApplicationRecord
  belongs_to :event

  validates :slug, presence: true, uniqueness: true
  validates :event, presence: true
end
