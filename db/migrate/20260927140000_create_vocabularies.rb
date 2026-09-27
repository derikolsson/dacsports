class CreateVocabularies < ActiveRecord::Migration[8.0]
  def up
    create_table :vocabularies do |t|
      t.bigint :channel_id
      t.text :phrases, null: false, default: ""
      t.string :mux_vocabulary_id
      t.datetime :synced_at
      t.string :sync_error
      t.timestamps
    end
    # NULLS NOT DISTINCT so there can only be one global (channel-less) vocabulary.
    add_index :vocabularies, :channel_id, unique: true, nulls_not_distinct: true

    add_column :channels, :captions_enabled, :boolean, null: false, default: false
    add_column :channels, :captions_synced_at, :datetime
    add_column :channels, :captions_sync_error, :string

    execute(<<~SQL)
      INSERT INTO vocabularies (phrases, created_at, updated_at)
      VALUES (#{quote("DAC Sports\nDallas Athletic Conference\nDallas College")}, NOW(), NOW())
    SQL
  end

  def down
    remove_column :channels, :captions_sync_error
    remove_column :channels, :captions_synced_at
    remove_column :channels, :captions_enabled
    drop_table :vocabularies
  end
end
