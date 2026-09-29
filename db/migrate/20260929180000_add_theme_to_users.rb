class AddThemeToUsers < ActiveRecord::Migration[8.0]
  def change
    # Light, dark, or "auto" to follow the system.
    add_column :users, :theme, :string, null: false, default: "auto"
  end
end
