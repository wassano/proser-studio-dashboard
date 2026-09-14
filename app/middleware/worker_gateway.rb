require "ipaddr"

# Trust proxy metadata only after authentication, before Rails parses host/IP.
class WorkerGateway
  def initialize(app) = @app = app
  def call(env)
    token = ENV["WORKER_ORIGIN_TOKEN"].to_s
    return @app.call(env) if token.empty?
    # Docker health checks remain local; public /up still requires the Worker.
    if env["PATH_INFO"] == "/up" && %w[127.0.0.1 ::1].include?(env["REMOTE_ADDR"])
      return @app.call(env)
    end
    supplied = env["HTTP_X_PROSER_EDGE_TOKEN"].to_s
    unless token.bytesize == 64 && ActiveSupport::SecurityUtils.secure_compare(token, supplied)
      return [403, { "content-type" => "application/json", "cache-control" => "no-store" }, ['{"error":"Origem não autorizada"}']]
    end
    ip = env["HTTP_X_PROSER_EDGE_IP"].to_s
    begin
      raise IPAddr::InvalidAddressError if ip.include?("/") || ip.empty?
      IPAddr.new(ip)
    rescue IPAddr::InvalidAddressError
      return [400, { "content-type" => "application/json" }, ['{"error":"Endereço do cliente inválido"}']]
    end
    public_origin = URI(ENV.fetch("API_URL", ENV.fetch("DASHBOARD_URL")))
    env.keys.grep(/\AHTTP_(?:FORWARDED|X_FORWARDED_.*|CLIENT_IP|X_REAL_IP)\z/).each { |key| env.delete(key) }
    env["REMOTE_ADDR"] = ip
    env["HTTP_X_FORWARDED_FOR"] = ip
    env["HTTP_HOST"] = public_origin.host
    env["HTTP_X_FORWARDED_HOST"] = public_origin.host
    env["HTTP_X_FORWARDED_PROTO"] = "https"
    env["rack.url_scheme"] = "https"
    @app.call(env)
  end
end
