Rack::Attack.cache.store = Rails.cache
Rack::Attack.throttle("device-registration/ip", limit: Integer(ENV.fetch("REGISTRATION_RATE_PER_HOUR", "60")), period: 3600) do |req|
  ActionDispatch::Request.new(req.env).remote_ip if req.path == "/api/v1/installations/register"
end
Rack::Attack.throttle("admin-api/ip", limit: 180, period: 60) do |req|
  ActionDispatch::Request.new(req.env).remote_ip if req.path.start_with?("/api/admin/") && !(req.put? && req.path.match?(%r{\A/api/admin/releases/\d+/uploads/[a-f0-9]{32}\z}))
end
Rack::Attack.throttle("device-api/ip", limit: 180, period: 60) do |req|
  ActionDispatch::Request.new(req.env).remote_ip if req.path.start_with?("/api/v1/installations/")
end
Rack::Attack.throttle("admin-auth/ip", limit: 30, period: 600) do |req|
  ActionDispatch::Request.new(req.env).remote_ip if req.path.start_with?("/auth/")
end
Rack::Attack.throttled_responder = ->(request) { [429, { "content-type" => "application/json", "retry-after" => "60" }, ['{"error":"Muitas tentativas. Tente novamente mais tarde."}']] }

Rack::Attack.throttle("upload-parts/ip", limit: 600, period: 60) do |req|
  ActionDispatch::Request.new(req.env).remote_ip if req.put? && req.path.match?(%r{\A/api/admin/releases/\d+/uploads/[a-f0-9]{32}\z})
end
