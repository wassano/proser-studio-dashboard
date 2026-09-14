class CreateReleaseUploads < ActiveRecord::Migration[8.1]
  def change
    create_table :release_uploads, id: :string do |t|
      t.references :release, null: false, foreign_key: true
      t.references :admin_session, null: false, foreign_key: true
      t.references :release_asset, foreign_key: true
      t.string :filename, null: false
      t.bigint :total_bytes, null: false
      t.bigint :received_bytes, null: false, default: 0
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_index :release_uploads, :expires_at
  end
end
