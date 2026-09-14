require_relative "boot"
require "rails"
require "active_support/core_ext/integer/time"
require "ipaddr"
require_relative "../app/middleware/worker_gateway"
require "active_record/railtie"
require "action_controller/railtie"
require "rails/test_unit/railtie"
Bundler.require(*Rails.groups)

module ProserDashboard
  class Application < Rails::Application
    config.load_defaults 8.1
    config.time_zone = "UTC"
    config.autoload_lib(ignore: %w[tasks])
    config.filter_parameters += %i[secret token authorization signature worker_origin_token x_proser_edge_token private_key activation_code code password]
    config.action_dispatch.cookies_same_site_protection = :lax
    config.session_store :cookie_store, key: Rails.env.production? ? "__Host-proser_admin" : "_proser_admin", httponly: true, same_site: :lax, secure: Rails.env.production?, expire_after: 8.hours
    config.action_controller.forgery_protection_origin_check = true
    config.middleware.insert_before 0, WorkerGateway
    config.middleware.use Rack::Attack
    config.action_dispatch.default_headers.merge!({
      "X-Content-Type-Options" => "nosniff", "X-Frame-Options" => "DENY",
      "Referrer-Policy" => "no-referrer", "Permissions-Policy" => "geolocation=(), camera=(), microphone=()",
      "Content-Security-Policy" => "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; font-src 'self'; object-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'"
    })
  end
end
