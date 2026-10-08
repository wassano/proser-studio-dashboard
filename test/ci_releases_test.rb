require "test_helper"

class CiReleasesTest < ActionDispatch::IntegrationTest
  setup { ENV["RELEASE_CI_TOKEN"] = "a" * 64 }
  teardown { ENV.delete("RELEASE_CI_TOKEN"); ReleaseUpload.where(ci_upload: true).each(&:remove_file) }
  def ci_headers = { "Authorization" => "Bearer #{ENV.fetch('RELEASE_CI_TOKEN')}", "CONTENT_TYPE" => "application/json" }
  def input(bytes = "MZci-installer")
    { release: { version: "1.22.0", target: "win-x64", channel: "stable", ci_run_url: "https://github.com/wassano/proser-studio-desktop/actions/runs/42", assets: [{ filename: "Proser.exe", size: bytes.bytesize, sha256: Digest::SHA256.hexdigest(bytes) }] } }
  end
  def create_release(bytes = "MZci-installer")
    post "/api/ci/releases", params: input(bytes).to_json, headers: ci_headers
    assert_response :success
    Release.find(response.parsed_body.fetch("id"))
  end
  test "CI cannot authenticate as admin or publish, and missing credentials fail closed" do
    post "/api/ci/releases", params: input.to_json, headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :unauthorized
    ENV.delete("RELEASE_CI_TOKEN")
    post "/api/ci/releases", params: input.to_json, headers: { "CONTENT_TYPE" => "application/json", "Authorization" => "Bearer #{'a' * 64}" }
    assert_response :unauthorized
    ENV["RELEASE_CI_TOKEN"] = "a" * 64
    release = create_release
    get "/api/admin/releases", headers: ci_headers
    assert_response :unauthorized
    post "/api/ci/releases/#{release.id}/publish", params: "{}", headers: ci_headers
    assert_response :not_found
    assert_equal "draft", release.reload.status
  end
  test "full chunked CI ingestion is retryable and requires a manual publication" do
    bytes = "MZci-installer"
    release = create_release(bytes)
    same = create_release(bytes)
    assert_equal release.id, same.id
    assert_equal 1, Release.count
    assert_raises(Policy::Denied) { release.publish! }
    post "/api/ci/releases/#{release.id}/complete", params: "{}", headers: ci_headers
    assert_response :unprocessable_entity
    base = "/api/ci/releases/#{release.id}/uploads"
    body = { upload: { filename: "Proser.exe", total_bytes: bytes.bytesize } }.to_json
    post base, params: body, headers: ci_headers
    assert_response :created
    upload = response.parsed_body
    post base, params: body, headers: ci_headers
    assert_equal upload.fetch("id"), response.parsed_body.fetch("id")
    path = "#{base}/#{upload.fetch('id')}"
    put path, params: bytes, headers: ci_headers.merge("CONTENT_TYPE" => "application/octet-stream", "X-Upload-Offset" => "0")
    assert_response :success
    put path, params: bytes, headers: ci_headers.merge("CONTENT_TYPE" => "application/octet-stream", "X-Upload-Offset" => "0")
    assert_response :success
    stub_request(:post, "https://appwrite.example.test/v1/storage/buckets/releases/files").to_return(status: 201, body: "{}")
    stub_request(:get, %r{https://appwrite.example.test/v1/storage/buckets/releases/files/[a-f0-9-]+}).to_return(status: 200, body: { sizeOriginal: bytes.bytesize, chunksUploaded: 1, chunksTotal: 1 }.to_json)
    post "#{path}/complete", params: "{}", headers: ci_headers
    assert_response :created
    post "#{path}/complete", params: "{}", headers: ci_headers
    assert_response :success
    assert_equal 1, release.release_assets.count
    post "/api/ci/releases/#{release.id}/complete", params: "{}", headers: ci_headers
    assert_response :success
    assert release.reload.ci_ready
    assert_equal "draft", release.status
    assert_equal ["github-actions"], AuditEvent.where("action LIKE 'release.%'").distinct.pluck(:actor)
    assert_equal release.id, create_release(bytes).id
    login
    post "/api/admin/releases/#{release.id}/publish", params: "{}", headers: admin_headers
    assert_response :success
    assert_equal "published", release.reload.status
  end
  test "CI rejects changed manifest and corrupted bytes without storing an asset" do
    release = create_release
    changed = input("MZchanged")
    post "/api/ci/releases", params: changed.to_json, headers: ci_headers
    assert_response :unprocessable_entity
    base = "/api/ci/releases/#{release.id}/uploads"
    post base, params: { upload: { filename: "Proser.exe", total_bytes: 14 } }.to_json, headers: ci_headers
    assert_response :created
    path = "#{base}/#{response.parsed_body.fetch('id')}"
    put path, params: "MZbad-data!!!!", headers: ci_headers.merge("CONTENT_TYPE" => "application/octet-stream", "X-Upload-Offset" => "0")
    assert_response :success
    post "#{path}/complete", params: "{}", headers: ci_headers
    assert_response :unprocessable_entity
    assert_equal 0, ReleaseAsset.count
    assert_not release.reload.ci_ready
  end
  test "macOS ingestion requires both a DMG installer and ZIP update" do
    body = input
    body[:release][:target] = "mac-arm64"
    body[:release][:assets] = [{ filename: "Proser.zip", size: 10, sha256: "b" * 64 }]
    post "/api/ci/releases", params: body.to_json, headers: ci_headers
    assert_response :unprocessable_entity
    body[:release][:assets] << { filename: "Proser.dmg", size: 12, sha256: "c" * 64 }
    post "/api/ci/releases", params: body.to_json, headers: ci_headers
    assert_response :success
  end
end
