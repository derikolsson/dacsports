class RemoveEventDateFromEvents < ActiveRecord::Migration[8.0]
  def change
    # First, ensure all existing events have start_at set from event_date if needed
    reversible do |dir|
      dir.up do
        # For any events that have event_date but no start_at, set start_at to the date at noon in their timezone
        execute <<-SQL
          UPDATE events
          SET start_at = event_date + interval '12 hours'
          WHERE start_at IS NULL AND event_date IS NOT NULL
        SQL
      end
    end

    # Make start_at required
    change_column_null :events, :start_at, false

    # Remove event_date column
    remove_column :events, :event_date, :date
  end
end
