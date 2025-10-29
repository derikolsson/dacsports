class ChangeEventVisitsToUseUuidPrimaryKey < ActiveRecord::Migration[8.0]
  def up
    # Add new UUID column
    add_column :event_visits, :uuid, :uuid, default: 'gen_random_uuid()', null: false

    # Backfill UUIDs for existing records (if any)
    execute "UPDATE event_visits SET uuid = gen_random_uuid() WHERE uuid IS NULL"

    # Remove old primary key
    remove_column :event_visits, :id

    # Rename uuid column to id
    rename_column :event_visits, :uuid, :id

    # Add new primary key
    execute "ALTER TABLE event_visits ADD PRIMARY KEY (id)"

    # Re-add indexes (they were dropped when we removed the old id column)
    # We only need indexes on session_id and event_id for analytics queries
    add_index :event_visits, :session_id unless index_exists?(:event_visits, :session_id)
    add_index :event_visits, :event_id unless index_exists?(:event_visits, :event_id)
  end

  def down
    # Remove UUID primary key
    execute "ALTER TABLE event_visits DROP CONSTRAINT event_visits_pkey"

    # Rename id back to uuid
    rename_column :event_visits, :id, :uuid

    # Create sequence for new bigint IDs
    execute "CREATE SEQUENCE IF NOT EXISTS event_visits_id_seq"

    # Add back bigint id column (nullable first, then backfill)
    add_column :event_visits, :id, :bigint

    # Backfill with sequential IDs
    execute <<-SQL
      UPDATE event_visits
      SET id = nextval('event_visits_id_seq')
    SQL

    # Now make it non-nullable and set as default
    change_column_null :event_visits, :id, false
    execute "ALTER TABLE event_visits ALTER COLUMN id SET DEFAULT nextval('event_visits_id_seq')"

    # Add primary key back
    execute "ALTER TABLE event_visits ADD PRIMARY KEY (id)"

    # Remove uuid column
    remove_column :event_visits, :uuid

    # Re-add indexes if needed
    add_index :event_visits, :session_id unless index_exists?(:event_visits, :session_id)
    add_index :event_visits, :event_id unless index_exists?(:event_visits, :event_id)
  end
end
