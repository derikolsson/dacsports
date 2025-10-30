class AddSessionBasedEventTracking < ActiveRecord::Migration[8.0]
  def up
    # Deduplicate existing EventVisits before adding unique index
    # Keep the record with the latest last_seen_at for each unique (session_id, event_id, event_status)
    duplicates = EventVisit.select(:session_id, :event_id, :event_status)
                           .group(:session_id, :event_id, :event_status)
                           .having('COUNT(*) > 1')
                           .pluck(:session_id, :event_id, :event_status)

    duplicates.each do |session_id, event_id, event_status|
      # Get all visits for this combination
      visits = EventVisit.where(
        session_id: session_id,
        event_id: event_id,
        event_status: event_status
      ).order(:started_at)

      # Keep the first record, merge data from others
      keeper = visits.first
      earliest_started_at = visits.minimum(:started_at)
      latest_last_seen_at = visits.maximum(:last_seen_at)

      # Update keeper with merged timestamps
      keeper.update!(
        started_at: earliest_started_at,
        last_seen_at: latest_last_seen_at
      )

      # Delete the duplicate records
      visits_to_delete = visits.offset(1)
      puts "  Deduplicating #{visits_to_delete.count} EventVisit(s) for session #{session_id}, event #{event_id}, status #{event_status}"
      puts "    Merged: started_at=#{earliest_started_at}, last_seen_at=#{latest_last_seen_at}"
      visits_to_delete.destroy_all
    end

    # Add composite unique index to prevent future duplicates
    add_index :event_visits, [ :session_id, :event_id, :event_status ],
              unique: true,
              name: 'index_event_visits_unique_session_event'
  end

  def down
    remove_index :event_visits, name: 'index_event_visits_unique_session_event'
  end
end
