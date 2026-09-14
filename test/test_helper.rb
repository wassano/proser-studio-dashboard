ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"
require "tmpdir"
WebMock.disable_net_connect!(allow_localhost: true)

module ProserTestSupport
  def setup
    super
    Rails.cache.clear
    @keydir = Dir.mktmpdir("proser-keys")
    @server_key = OpenSSL::PKey.generate_key("ED25519")
    File.write(File.join(@keydir, "license.pem"), @server_key.private_to_pem)
    ENV["LICENSE_PRIVATE_KEY_PATH"] = File.join(@keydir, "license.pem")
    ENV["APPWRITE_ENDPOINT"] = "https://appwrite.example.test/v1"
    ENV["APPWRITE_PROJECT_ID"] = "proser"
    ENV["APPWRITE_AUTH_KEY"] = "test-auth-key"
    ENV["APPWRITE_STORAGE_KEY"] = "test-storage-key"
    ENV["APPWRITE_RELEASE_BUCKET"] = "releases"
    ENV["ADMIN_GOOGLE_EMAILS"] = "dwassano@gmail.com"
    ENV["DASHBOARD_URL"] = "http://www.example.com"
    ENV.delete("API_URL")
    @plan = Plan.create!(name: "Studio", features: Plan::FEATURES.to_h { |f| [f, true] }, limits: Plan::LIMITS, offline_hours: 24)
    RegistrationSetting.find_or_initialize_by(id: 1).update!(plan: @plan, installation_limit: 20, registration_enabled: true)
  end
  def teardown
    FileUtils.remove_entry(@keydir) if @keydir
    super
  end
  def device_key = OpenSSL::PKey.generate_key("ED25519")
  def metadata
    { computer_name: "PC-PALCO", os: "win32 10.0", arch: "x64", app_version: "1.18.0", target: "win-x64" }
  end
  def signed_headers(key, path, body, nonce: SecureRandom.hex(16), timestamp: Time.current.to_i)
    canonical = ["POST", path, timestamp.to_s, nonce, Digest::SHA256.hexdigest(body)].join("\n")
    { "CONTENT_TYPE" => "application/json", "X-Proser-Device" => Digest::SHA256.hexdigest(key.public_to_der), "X-Proser-Nonce" => nonce, "X-Proser-Time" => timestamp.to_s, "X-Proser-Signature" => Base64.strict_encode64(key.sign(nil, canonical)) }
  end
  def register_device(key = device_key)
    path = "/api/v1/installations/register"
    body = JSON.generate(metadata.merge(public_key: key.public_to_pem))
    post path, params: body, headers: signed_headers(key, path, body)
    assert_response :success
    [key, Installation.find_by!(device_id: Digest::SHA256.hexdigest(key.public_to_der))]
  end
  def decoded
    envelope = response.parsed_body
    assert @server_key.verify(nil, Base64.urlsafe_decode64(envelope.fetch("signature")), "proser-v1.#{envelope.fetch('kid')}.#{envelope.fetch('payload')}")
    JSON.parse(Base64.urlsafe_decode64(envelope.fetch("payload")))
  end
  def login(email: "dwassano@gmail.com", verified: true, provider: "google")
    get "/auth/google"
    success = URI.decode_www_form(URI(response.location).query).to_h.fetch("success")
    state = URI.decode_www_form(URI(success).query).to_h.fetch("state")
    stub_request(:post, "https://appwrite.example.test/v1/account/sessions/token").to_return(status: 201, body: { secret: "session-secret" }.to_json)
    stub_request(:get, "https://appwrite.example.test/v1/account").with(headers: { "X-Appwrite-Session" => "session-secret" }).to_return(status: 200, body: { email: email, emailVerification: verified, status: true }.to_json)
    stub_request(:get, "https://appwrite.example.test/v1/account/sessions/current").to_return(status: 200, body: { provider: provider }.to_json)
    stub_request(:get, "https://appwrite.example.test/v1/account/identities").to_return(status: 200, body: { identities: [{ provider: provider, providerEmail: email, providerUid: "google-user-123", providerAccessToken: "google-test-token" }] }.to_json)
    stub_request(:get, "https://openidconnect.googleapis.com/v1/userinfo").with(headers: { "Authorization" => "Bearer google-test-token" }).to_return(status: 200, body: { email: email, email_verified: verified, sub: "google-user-123" }.to_json)
    stub_request(:delete, "https://appwrite.example.test/v1/account/sessions/current").to_return(status: 204)
    get "/auth/callback", params: { state: state, userId: "admin", secret: "oauth-token" }
    if response.redirect?
      @login_redirect = response.location
      get "/api/session"
      @csrf = response.parsed_body.fetch("csrf_token")
    end
  end
  def admin_headers = { "X-CSRF-Token" => @csrf, "CONTENT_TYPE" => "application/json" }
end

class ActiveSupport::TestCase
  include ProserTestSupport
end
