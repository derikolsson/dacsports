class AddAcquisitionToSessions < ActiveRecord::Migration[8.0]
  def change
    # How an on-site session arrived, captured on its first request.
    change_table :sessions, bulk: true do |t|
      t.string :landing_referrer_host
      t.string :landing_path
      t.string :utm_source
      t.string :utm_medium
      t.string :utm_campaign
    end
  end
end
