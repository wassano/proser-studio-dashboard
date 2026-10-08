require "test_helper"

class AdminTest < ActionDispatch::IntegrationTest
  test "only verified Google allowlist can administer with CSRF protection" do
    get "/api/admin/installations"
    assert_response :unauthorized
    login(email: "intruso@example.com")
    assert_response :unprocessable_entity
    assert_equal 0, AdminSession.count
    login(verified: false)
    assert_response :unprocessable_entity
    login(provider: "email")
    assert_response :unprocessable_entity
    login
    assert_response :success
    get "/api/admin/settings"
    assert_equal 20, response.parsed_body["installation_limit"]
    patch "/api/admin/settings", params: { settings: { installation_limit: 50 } }.to_json, headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :unprocessable_entity
    assert_equal 20, RegistrationSetting.current.installation_limit
    patch "/api/admin/settings", params: { settings: { installation_limit: 50 } }.to_json, headers: admin_headers
    assert_response :success
    assert_equal 50, RegistrationSetting.current.installation_limit
    assert_equal 1, AuditEvent.where(action: "settings.update").count
  end
  test "OAuth callback without browser state is rejected" do
    get "/auth/callback", params: { state: "a" * 64, userId: "admin", secret: "secret" }
    assert_response :unprocessable_entity
    assert_equal 0, AdminSession.count
  end
  test "admin can revoke and approve subject to global and per-license limits" do
    _, first = register_device
    RegistrationSetting.current.update!(installation_limit: 1)
    _, second = register_device
    login
    post "/api/admin/installations/#{second.id}/approve", params: {}.to_json, headers: admin_headers
    assert_response :unprocessable_entity
    patch "/api/admin/installations/#{first.id}", params: { installation: { status: "revoked" } }.to_json, headers: admin_headers
    assert_response :success
    post "/api/admin/installations/#{second.id}/approve", params: {}.to_json, headers: admin_headers
    assert_response :success
    assert_equal "active", second.reload.status
    assert_equal 1, Installation.where(status: "active").count
    patch "/api/admin/installations/#{first.id}", params: { installation: { status: "active" } }.to_json, headers: admin_headers
    assert_response :unprocessable_entity
  end
  test "logout and inactivity invalidate sessions" do
    login
    delete "/api/session", headers: admin_headers
    assert_response :no_content
    get "/api/admin/licenses"
    assert_response :unauthorized
    login
    AdminSession.last.update!(last_seen_at: 2.hours.ago)
    get "/api/admin/licenses"
    assert_response :unauthorized
  end
  test "admin assigns an existing license without bypassing its device capacity" do
    _, first = register_device
    _, second = register_device
    login
    post "/api/admin/licenses", params: { license: { name: "Auditório", plan_id: @plan.id, max_devices: 1 } }.to_json, headers: admin_headers
    assert_response :created
    assigned = License.find(response.parsed_body.fetch("id"))
    post "/api/admin/installations/#{first.id}/approve", params: { license_id: assigned.id }.to_json, headers: admin_headers
    assert_response :success
    assert_equal assigned, first.reload.license
    previous = second.license
    post "/api/admin/installations/#{second.id}/approve", params: { license_id: assigned.id }.to_json, headers: admin_headers
    assert_response :unprocessable_entity
    assert_equal previous, second.reload.license
    assert_equal 2, Installation.where(status: "active").count
  end
  test "dashboard keeps OAuth on its own origin while devices use the separate API" do
    ENV["DASHBOARD_URL"] = "https://app.proser.studio"
    ENV["API_URL"] = "https://api.proser.studio"
    host! "app.proser.studio"
    https!
    get "/auth/google"
    success = URI.decode_www_form(URI(response.location).query).to_h.fetch("success")
    assert_equal "app.proser.studio", URI(success).host
    assert_equal "/auth/callback", URI(success).path
    login
    assert_response :success
    assert_equal "app.proser.studio", URI(@login_redirect).host
    path = "/api/admin/settings"
    body = { settings: { installation_limit: 25 } }.to_json
    patch path, params: body, headers: admin_headers.merge("Origin" => "https://app.proser.studio")
    assert_response :success
    patch path, params: body, headers: { "CONTENT_TYPE" => "application/json", "Origin" => "https://app.proser.studio" }
    assert_response :unprocessable_entity
    patch path, params: body, headers: admin_headers.merge("Origin" => "https://evil.proser.studio")
    assert_response :unprocessable_entity
    patch path, params: body, headers: admin_headers.merge("Origin" => "null")
    assert_response :unprocessable_entity
    get "/auth/failure"
    assert_redirected_to "https://app.proser.studio/?login=failed"
  end

end
