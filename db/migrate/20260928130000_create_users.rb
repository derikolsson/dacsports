class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.string :email_address, null: false
      t.string :name
      t.string :password_digest
      t.boolean :admin, null: false, default: false
      t.bigint :invited_by_id
      t.datetime :invitation_accepted_at
      t.datetime :deactivated_at
      t.datetime :last_signed_in_at
      t.string :webauthn_id, null: false
      t.timestamps
    end
    add_index :users, :email_address, unique: true
    add_index :users, :webauthn_id, unique: true

    create_table :user_sessions do |t|
      t.bigint :user_id, null: false
      t.string :ip_address
      t.string :user_agent
      t.timestamps
    end
    add_index :user_sessions, :user_id

    create_table :passkeys do |t|
      t.bigint :user_id, null: false
      t.string :external_id, null: false
      t.string :public_key, null: false
      t.bigint :sign_count, null: false, default: 0
      t.string :name, null: false
      t.datetime :last_used_at
      t.timestamps
    end
    add_index :passkeys, :user_id
    add_index :passkeys, :external_id, unique: true
  end
end
