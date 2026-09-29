# Mux Data's views, unique viewers and watch time for one Chicago day, video, audience
# and stream type. Written only by MuxDataImport.
class MuxDailyStat < ApplicationRecord
  # custom_1 was empty before players were tagged, so those views can't be placed.
  UNKNOWN = "unknown".freeze

  # Mux's stream_type values, keyed like ReportsQuery::EVENT_COLUMNS.
  STREAM_TYPES = { "live" => "live", "vod" => "on-demand" }.freeze
end
