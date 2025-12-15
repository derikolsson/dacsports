class Team < ApplicationRecord
  DALLAS_COLLEGE_CAMPUSES = [
    "Brookhaven",
    "Cedar Valley",
    "Eastfield",
    "El Centro",
    "Mountain View",
    "North Lake",
    "Richland"
  ].freeze

  has_many :event_teams, dependent: :destroy
  has_many :events, through: :event_teams

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  scope :alphabetical, -> { order(:name) }
end
