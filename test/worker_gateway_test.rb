require "test_helper"

class WorkerGatewayTest < ActiveSupport::TestCase
  test "only authenticated proxy can provide public host and client IP" do
    previous = ENV["WORKER_ORIGIN_TOKEN"]
    ENV["WORKER_ORIGIN_TOKEN"] = "a" * 64
    ENV["DASHBOARD_URL"] = "https://app.proser.studio"
    ENV["API_URL"] = "https://api.proser.studio"
    captured = nil
    gateway = WorkerGateway.new(->(env) { captured = env; [200, {}, []] })
    input = { "PATH_INFO" => "/api/session", "REMOTE_ADDR" => "172.29.80.3", "HTTP_HOST" => "rails.example.test", "HTTP_X_FORWARDED_FOR" => "127.0.0.1", "HTTP_X_PROSER_EDGE_IP" => "203.0.113.20" }
    assert_equal 403, gateway.call(input.dup).first
    assert_nil captured
    assert_equal 200, gateway.call(input.merge("HTTP_X_PROSER_EDGE_TOKEN" => "a" * 64)).first
    assert_equal "api.proser.studio", captured["HTTP_HOST"]
    assert_equal "203.0.113.20", ActionDispatch::Request.new(captured).remote_ip
    assert_equal "https", captured["rack.url_scheme"]
    assert_equal 400, gateway.call(input.merge("HTTP_X_PROSER_EDGE_TOKEN" => "a" * 64, "HTTP_X_PROSER_EDGE_IP" => "127.0.0.1/8")).first
  ensure
    ENV["WORKER_ORIGIN_TOKEN"] = previous
  end
end

class WorkerGatewayIntegrationTest < ActionDispatch::IntegrationTest
  test "signed installation retains the observed client IP through the gateway" do
    previous = ENV["WORKER_ORIGIN_TOKEN"]
    ENV["WORKER_ORIGIN_TOKEN"] = "a" * 64
    ENV["DASHBOARD_URL"] = "https://app.proser.studio"
    ENV["API_URL"] = "https://api.proser.studio"
    host! "rails.example.test"
    key = device_key
    path = "/api/v1/installations/register"
    body = JSON.generate(metadata.merge(public_key: key.public_to_pem))
    headers = signed_headers(key, path, body).merge("X-Proser-Edge-Token" => "a" * 64, "X-Proser-Edge-IP" => "203.0.113.20", "X-Forwarded-For" => "127.0.0.1")
    post path, params: body, headers: headers
    assert_response :success
    assert_equal "active", decoded["status"]
    assert_equal "203.0.113.20", Installation.last.last_ip
    get "/api/admin/licenses"
    assert_response :forbidden
  ensure
    ENV["WORKER_ORIGIN_TOKEN"] = previous
  end
end
