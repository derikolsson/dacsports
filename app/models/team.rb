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

  TEAM_COLORS = {
    "brookhaven"    => { primary: "#1B5E20", secondary: "#000000", abbr: "BH", mascot: "Bears" },
    "cedar-valley"  => { primary: "#FFD700", secondary: "#000000", abbr: "CV", text: "#000000", mascot: "Suns" },
    "eastfield"     => { primary: "#E86100", secondary: "#1565C0", abbr: "EF", mascot: "Harvester Bees" },
    "el-centro"     => { primary: "#1B365D", secondary: "#A9A9A9", abbr: "EC", mascot: "Eagles" },
    "mountain-view" => { primary: "#F4B41A", secondary: "#003087", abbr: "MV", text: "#003087", mascot: "Lions" },
    "north-lake"    => { primary: "#228B22", secondary: "#1976D2", abbr: "NL", mascot: "Blazers" },
    "richland"      => { primary: "#2D2A5E", secondary: "#0d964e", abbr: "RC", mascot: "Thunderducks" }
  }.freeze

  has_many :event_teams, dependent: :destroy
  has_many :events, through: :event_teams

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  scope :alphabetical, -> { order(:name) }

  # Logo helpers
  def logo_path
    "/team-logos/#{slug}.png"
  end

  def mini_logo_path
    "/team-logos/mini/#{slug}.png"
  end

  def logo_exists?
    File.exist?(Rails.root.join("public", "team-logos", "#{slug}.png"))
  end

  def mini_logo_exists?
    File.exist?(Rails.root.join("public", "team-logos", "mini", "#{slug}.png"))
  end

  def team_colors
    TEAM_COLORS[slug] || { primary: "#6c757d", secondary: "#ffffff", abbr: name[0..2].upcase }
  end

  def primary_color
    team_colors[:primary]
  end

  def secondary_color
    team_colors[:secondary]
  end

  def abbreviation
    team_colors[:abbr]
  end

  def text_color
    team_colors[:text] || primary_color
  end

  def mascot
    team_colors[:mascot]
  end
end
