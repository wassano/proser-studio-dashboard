require "test_helper"

class LicensingTest < ActionDispatch::IntegrationTest
  test "registration auto approves, signs entitlements and records observations" do
    key, installation = register_device
    payload = decoded
    assert_equal "active", payload["status"]
    assert_equal 170, payload.dig("limits", "fixtures")
    assert_equal "PC-PALCO", installation.computer_name
    assert installation.activated_at
    assert installation.last_seen_at
    assert installation.last_ip
    assert_nil installation.license.expires_at
    assert_equal 1, AuditEvent.where(action: "installation.register").count
    register_device(key)
    assert_equal 1, Installation.count
    assert_equal 1, License.count
  end
  test "global cap blocks new installations and reenrollment cannot reset revocation" do
    RegistrationSetting.current.update!(installation_limit: 1)
    first_key, first = register_device
    _, second = register_device
    assert_equal "pending", decoded["status"]
    assert_nil second.license
    first.update!(status: "revoked")
    register_device(first_key)
    assert_equal "revoked", decoded["status"]
    assert_equal "revoked", first.reload.status
  end
  test "paused registration fails closed" do
    RegistrationSetting.current.update!(registration_enabled: false)
    register_device
    assert_equal "pending", decoded["status"]
    assert_equal 0, License.count
  end
  test "rejects tampering replay timestamps and substituted public keys" do
    key = device_key
    path = "/api/v1/installations/register"
    body = metadata.merge(public_key: key.public_to_pem).to_json
    headers = signed_headers(key, path, body)
    post path, params: body, headers: headers
    assert_response :success
    post path, params: body, headers: headers
    assert_response :unauthorized
    post path, params: body.sub("PC-PALCO", "ALTERADO"), headers: signed_headers(key, path, body)
    assert_response :unauthorized
    post path, params: body, headers: signed_headers(key, path, body, timestamp: 1.hour.ago.to_i)
    assert_response :unauthorized
    other = metadata.merge(public_key: device_key.public_to_pem).to_json
    post path, params: other, headers: signed_headers(key, path, other)
    assert_response :unauthorized
    assert_equal 1, Installation.count
  end
  test "heartbeat uses server permissions expiration and observes last use" do
    key, installation = register_device
    installation.license.update!(limit_overrides: { fixtures: 2 }, feature_overrides: { video: false })
    path = "/api/v1/installations/heartbeat"
    body = metadata.merge(computer_name: "PC-NOVO", target: "mac-arm64", status: "active", features: { video: true }).to_json
    post path, params: body, headers: signed_headers(key, path, body)
    assert_equal false, decoded.dig("features", "video")
    assert_equal 2, decoded.dig("limits", "fixtures")
    assert_equal "win-x64", installation.reload.target
    assert_equal "PC-NOVO", installation.computer_name
    installation.license.update!(expires_at: 1.minute.ago)
    post path, params: body, headers: signed_headers(key, path, body)
    assert_equal "blocked", decoded["status"]
  end
  test "license minimum version requires update and invalid quotas are rejected" do
    _, installation = register_device
    installation.license.update!(minimum_version: "1.19.0")
    assert_equal "upgrade_required", installation.reload.access_status
    assert_not installation.license.update(limit_overrides: { fixtures: -1 })
    assert_not @plan.update(features: { "invented" => true })
    assert_not @plan.update(limits: { "fixtures" => 171 })
  end
end
