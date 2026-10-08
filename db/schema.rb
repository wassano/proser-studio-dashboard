# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_08_000100) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "admin_sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "expires_at", null: false
    t.datetime "last_seen_at", null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["token_digest"], name: "index_admin_sessions_on_token_digest", unique: true
  end

  create_table "audit_events", force: :cascade do |t|
    t.string "action", null: false
    t.string "actor", null: false
    t.datetime "created_at", null: false
    t.json "details", default: {}, null: false
    t.string "ip"
    t.string "subject"
  end

  create_table "download_grants", force: :cascade do |t|
    t.datetime "expires_at", null: false
    t.integer "installation_id", null: false
    t.integer "release_id", null: false
    t.string "token_digest", null: false
    t.index ["installation_id"], name: "index_download_grants_on_installation_id"
    t.index ["release_id"], name: "index_download_grants_on_release_id"
    t.index ["token_digest"], name: "index_download_grants_on_token_digest", unique: true
  end

  create_table "installations", force: :cascade do |t|
    t.datetime "activated_at"
    t.string "app_version", null: false
    t.string "arch", null: false
    t.string "computer_name", null: false
    t.datetime "created_at", null: false
    t.string "device_id", null: false
    t.string "last_ip"
    t.datetime "last_seen_at"
    t.integer "license_id"
    t.string "location"
    t.string "os", null: false
    t.text "public_key", null: false
    t.string "status", default: "pending", null: false
    t.string "target", null: false
    t.datetime "updated_at", null: false
    t.index ["device_id"], name: "index_installations_on_device_id", unique: true
    t.index ["license_id"], name: "index_installations_on_license_id"
    t.index ["status", "last_seen_at"], name: "index_installations_on_status_and_last_seen_at"
  end

  create_table "licenses", force: :cascade do |t|
    t.string "channel", default: "stable", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.json "feature_overrides", default: {}, null: false
    t.json "limit_overrides", default: {}, null: false
    t.integer "max_devices", default: 1, null: false
    t.string "minimum_version", default: "1.18.0", null: false
    t.string "name", null: false
    t.integer "plan_id", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.index ["plan_id"], name: "index_licenses_on_plan_id"
  end

  create_table "plans", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "features", default: {}, null: false
    t.json "limits", default: {}, null: false
    t.string "name", null: false
    t.integer "offline_hours", default: 24, null: false
    t.datetime "updated_at", null: false
  end

  create_table "registration_settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "installation_limit", default: 20, null: false
    t.integer "plan_id", null: false
    t.boolean "registration_enabled", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["plan_id"], name: "index_registration_settings_on_plan_id"
  end

  create_table "release_assets", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.integer "release_id", null: false
    t.string "sha256", null: false
    t.string "sha512", null: false
    t.bigint "size", null: false
    t.string "storage_id", null: false
    t.datetime "updated_at", null: false
    t.index ["release_id", "filename"], name: "index_release_assets_on_release_id_and_filename", unique: true
    t.index ["release_id"], name: "index_release_assets_on_release_id"
    t.index ["storage_id"], name: "index_release_assets_on_storage_id", unique: true
  end

  create_table "release_uploads", id: :string, force: :cascade do |t|
    t.integer "admin_session_id"
    t.boolean "ci_upload", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "filename", null: false
    t.bigint "received_bytes", default: 0, null: false
    t.integer "release_asset_id"
    t.integer "release_id", null: false
    t.bigint "total_bytes", null: false
    t.datetime "updated_at", null: false
    t.index ["admin_session_id"], name: "index_release_uploads_on_admin_session_id"
    t.index ["expires_at"], name: "index_release_uploads_on_expires_at"
    t.index ["release_asset_id"], name: "index_release_uploads_on_release_asset_id"
    t.index ["release_id"], name: "index_release_uploads_on_release_id"
  end

  create_table "releases", force: :cascade do |t|
    t.string "channel", default: "stable", null: false
    t.json "ci_expected_assets", default: [], null: false
    t.boolean "ci_ready", default: false, null: false
    t.string "ci_run_url"
    t.datetime "created_at", null: false
    t.text "notes", default: "", null: false
    t.datetime "published_at"
    t.string "status", default: "draft", null: false
    t.string "target", null: false
    t.datetime "updated_at", null: false
    t.string "version", null: false
    t.index ["version", "target", "channel"], name: "index_releases_on_version_and_target_and_channel", unique: true
  end

  create_table "request_nonces", force: :cascade do |t|
    t.string "digest", null: false
    t.datetime "expires_at", null: false
    t.index ["digest"], name: "index_request_nonces_on_digest", unique: true
    t.index ["expires_at"], name: "index_request_nonces_on_expires_at"
  end

  add_foreign_key "download_grants", "installations"
  add_foreign_key "download_grants", "releases"
  add_foreign_key "installations", "licenses"
  add_foreign_key "licenses", "plans"
  add_foreign_key "registration_settings", "plans"
  add_foreign_key "release_assets", "releases"
  add_foreign_key "release_uploads", "admin_sessions"
  add_foreign_key "release_uploads", "release_assets"
  add_foreign_key "release_uploads", "releases"
end
