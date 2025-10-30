class CreateEventSlugs < ActiveRecord::Migration[8.0]
  def change
    create_table :event_slugs do |t|
      t.references :event, null: false, foreign_key: true
      t.string :slug, null: false

      t.timestamps
    end
    add_index :event_slugs, :slug, unique: true
  end
end
