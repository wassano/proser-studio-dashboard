class CreateLicensing < ActiveRecord::Migration[8.1]
  def change
    create_table :plans do |t|
      t.string :name, null: false
      t.json :features, null: false, default: {}
      t.json :limits, null: false, default: {}
      t.integer :offline_hours, null: false, default: 24
      t.timestamps
    end
    create_table :licenses do |t|
      t.references :plan, null: false, foreign_key: true
      t.string :name, null: false
      t.string :status, null: false, default: "active"
      t.integer :max_devices, null: false, default: 1
      t.datetime :expires_at
      t.string :channel, null: false, default: "stable"
      t.string :minimum_version, null: false, default: "1.18.0"
      t.json :feature_overrides, null: false, default: {}
      t.json :limit_overrides, null: false, default: {}
      t.timestamps
    end
    create_table :installations do |t|
      t.references :license, foreign_key: true
      t.string :device_id, null: false
      t.text :public_key, null: false
      t.string :status, null: false, default: "pending"
      t.string :computer_name, null: false
      t.string :os, null: false
      t.string :arch, null: false
      t.string :app_version, null: false
      t.string :target, null: false
      t.string :last_ip
      t.string :location
      t.datetime :activated_at
      t.datetime :last_seen_at
      t.timestamps
    end
    add_index :installations, :device_id, unique: true
    add_index :installations, [:status, :last_seen_at]
    create_table :request_nonces do |t|
      t.string :digest, null: false
      t.datetime :expires_at, null: false
    end
    add_index :request_nonces, :digest, unique: true
    add_index :request_nonces, :expires_at
    create_table :admin_sessions do |t|
      t.string :token_digest, null: false
      t.string :email, null: false
      t.datetime :expires_at, null: false
      t.datetime :last_seen_at, null: false
      t.timestamps
    end
    add_index :admin_sessions, :token_digest, unique: true
    create_table :audit_events do |t|
      t.string :actor, null: false
      t.string :action, null: false
      t.string :subject
      t.string :ip
      t.json :details, null: false, default: {}
      t.datetime :created_at, null: false
    end
    create_table :releases do |t|
      t.string :version, null: false
      t.string :target, null: false
      t.string :channel, null: false, default: "stable"
      t.text :notes, null: false, default: ""
      t.string :status, null: false, default: "draft"
      t.datetime :published_at
      t.timestamps
    end
    add_index :releases, [:version, :target, :channel], unique: true
    create_table :release_assets do |t|
      t.references :release, null: false, foreign_key: true
      t.string :storage_id, null: false
      t.string :filename, null: false
      t.bigint :size, null: false
      t.string :sha512, null: false
      t.string :sha256, null: false
      t.timestamps
    end
    add_index :release_assets, :storage_id, unique: true
    add_index :release_assets, [:release_id, :filename], unique: true
    create_table :download_grants do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :release, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
    end
    add_index :download_grants, :token_digest, unique: true
    create_table :registration_settings do |t|
      t.references :plan, null: false, foreign_key: true
      t.integer :installation_limit, null: false, default: 20
      t.boolean :registration_enabled, null: false, default: true
      t.timestamps
    end
  end
end
