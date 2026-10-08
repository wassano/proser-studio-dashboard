class AddCiReleases < ActiveRecord::Migration[8.1]
  def change
    add_column :releases, :ci_run_url, :string
    add_column :releases, :ci_expected_assets, :json, null: false, default: []
    add_column :releases, :ci_ready, :boolean, null: false, default: false
    change_column_null :release_uploads, :admin_session_id, true
    add_column :release_uploads, :ci_upload, :boolean, null: false, default: false
  end
end
