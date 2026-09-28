class AddReportingIndexesToEventVisits < ActiveRecord::Migration[8.0]
  def change
    # Reports filter by when viewing happened, per audience; the dashboard asks who
    # was seen in the last few minutes.
    add_index :event_visits, [ :source, :started_at ]
    add_index :event_visits, :last_seen_at
  end
end
