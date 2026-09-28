class AddFirstPlayedAtToEventVisits < ActiveRecord::Migration[8.0]
  def change
    # When the viewer first pressed play (or autoplay started). Null means the page was
    # open but nothing played, or the visit predates play tracking.
    add_column :event_visits, :first_played_at, :datetime
    add_index :event_visits, :first_played_at
  end
end
