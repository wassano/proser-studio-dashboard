Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.force_ssl = true
  config.assume_ssl = true # Only reachable through the TLS reverse proxy; no public Rails port.
  config.ssl_options = { hsts: { expires: 1.year, subdomains: true } }
  config.hosts = [URI(ENV.fetch("API_URL")).host]
  config.action_dispatch.trusted_proxies = ENV.fetch("TRUSTED_PROXY_CIDRS").split(",").map { |cidr| IPAddr.new(cidr.strip) }
  config.cache_store = :redis_cache_store, { url: ENV.fetch("REDIS_URL"), namespace: "proser", error_handler: ->(**) { raise "Redis indisponível" } }
  config.secret_key_base = ENV.fetch("SECRET_KEY_BASE")
  config.log_level = :info
  config.logger = ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new($stdout))
  config.public_file_server.enabled = true
  config.public_file_server.headers = config.action_dispatch.default_headers.merge("Cache-Control" => "no-cache")
end
