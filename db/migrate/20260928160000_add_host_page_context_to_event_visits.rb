class AddHostPageContextToEventVisits < ActiveRecord::Migration[8.0]
  def change
    # Which partner page an embed view happened on, and what sent the viewer there.
    # Written on the visit's first save.
    change_table :event_visits, bulk: true do |t|
      t.string :page_url
      t.string :page_title
      t.string :host_referrer_origin
      t.string :utm_source
      t.string :utm_medium
      t.string :utm_campaign
    end
  end
end
