require "open3"
require "openssl"
require "tmpdir"
require "uri"

# Use only the disposable PostgreSQL database supplied by CI/local tests.
database = URI(ENV.fetch("DATABASE_URL"))
unless %w[127.0.0.1 localhost].include?(database.host) && database.path == "/proser_test"
  abort "Production migration regression requires a local proser_test database"
end

Dir.mktmpdir("proser-production-migration-") do |dir|
  key = File.join(dir, "license.pem")
  File.write(key, OpenSSL::PKey.generate_key("ED25519").private_to_pem, perm: 0o600)
  # A dump here must fail: the parent directory deliberately does not exist.
  schema = File.join(dir, "unwritable", "schema.rb")
  env = {
    "RAILS_ENV" => "production", "SCHEMA" => schema,
    "DASHBOARD_URL" => "https://dashboard.example.test", "API_URL" => "https://api.example.test",
    "ADMIN_GOOGLE_EMAILS" => "admin@example.test", "SECRET_KEY_BASE" => "a" * 128,
    "REDIS_URL" => "redis://127.0.0.1:6379/0", "TRUSTED_PROXY_CIDRS" => "127.0.0.0/8",
    "APPWRITE_ENDPOINT" => "https://appwrite.example.test/v1", "APPWRITE_PROJECT_ID" => "test-project",
    "APPWRITE_AUTH_KEY" => "test-auth-key", "APPWRITE_STORAGE_KEY" => "test-storage-key",
    "APPWRITE_RELEASE_BUCKET" => "test-releases", "LICENSE_PRIVATE_KEY_PATH" => key,
    "RELEASE_CI_TOKEN" => nil, "WORKER_ORIGIN_TOKEN" => nil
  }
  out, err, status = Open3.capture3(env, "bundle", "exec", "rails", "db:migrate", "db:abort_if_pending_migrations")
  abort "#{out}\n#{err}" unless status.success?
  abort "Production migrations attempted to generate a schema file" if File.exist?(schema)
  puts "Production migrations completed without writing the schema; no pending migrations"
end
