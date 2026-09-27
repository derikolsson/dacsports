class RemoveLiveEmbedCodeFromEvents < ActiveRecord::Migration[8.0]
  def change
    remove_column :events, :live_embed_code, :text
  end
end
