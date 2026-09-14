Rails.application.configure do
  config.enable_reloading = true
  config.eager_load = false
  config.consider_all_requests_local = true
  config.cache_store = :memory_store
  config.hosts += ["localhost", "127.0.0.1"]
  config.secret_key_base = ENV.fetch("SECRET_KEY_BASE", "development-only-" * 8)
  config.public_file_server.enabled = true
end
