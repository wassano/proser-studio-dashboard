require "test_helper"

class ReleasesTest < ActionDispatch::IntegrationTest
  test "drafts do not update; published immutable manifests require device authorization" do
    key, installation = register_device
    release = Release.create!(version: "1.19.0", target: "win-x64")
    bytes = "MZtest-update"
    asset = release.release_assets.create!(filename: "Proser-1.19.0.exe", storage_id: SecureRandom.uuid, size: bytes.bytesize, sha512: Base64.strict_encode64(Digest::SHA512.digest(bytes)), sha256: Digest::SHA256.hexdigest(bytes))
    path = "/api/v1/installations/update"
    post path, params: "{}", headers: signed_headers(key, path, "{}")
    assert_nil decoded["release"]
    release.publish!
    post path, params: "{}", headers: signed_headers(key, path, "{}")
    descriptor = decoded.fetch("release")
    assert_equal "1.19.0", descriptor.dig("manifest", "version")
    endpoint = "/api/v1/updates/#{release.id}/latest.yml"
    get endpoint
    assert_response :unauthorized
    grant_headers = { "Authorization" => "Bearer #{descriptor.fetch('token')}" }
    get endpoint, headers: grant_headers
    assert_response :success
    assert_equal asset.sha512, YAML.safe_load(response.body).fetch("files").first.fetch("sha512")
    stub_request(:get, "https://appwrite.example.test/v1/storage/buckets/releases/files/#{asset.storage_id}/download").with(headers: { "X-Appwrite-Key" => "test-storage-key" }).to_return(status: 200, body: bytes)
    get "/api/v1/updates/#{release.id}/files/#{asset.id}/#{asset.filename}", headers: grant_headers
    assert_response :success
    assert_equal bytes, response.body
    assert_raises(Policy::Denied) { release.publish! }
    installation.update!(status: "revoked")
    get endpoint, headers: grant_headers
    assert_response :unauthorized
  end
  test "withdrawal invalidates grants and lower versions cannot be published" do
    _, installation = register_device
    release = Release.create!(version: "1.20.0", target: "win-x64")
    release.release_assets.create!(filename: "Proser.exe", storage_id: SecureRandom.uuid, size: 10, sha512: "sha", sha256: "sha")
    release.publish!
    previous = Release.create!(version: "1.19.0", target: "win-x64")
    previous.release_assets.create!(filename: "Proser.exe", storage_id: SecureRandom.uuid, size: 10, sha512: "sha", sha256: "sha")
    assert_raises(Policy::Denied) { previous.publish! }
    release.update!(status: "withdrawn")
    assert_equal 0, Release.where(status: "published").count
  end
  test "upload requires auth CSRF valid filename and file magic" do
    release = Release.create!(version: "1.19.0", target: "win-x64")
    login
    file = Tempfile.new(["bad", ".exe"])
    file.write("not an executable"); file.flush
    upload = Rack::Test::UploadedFile.new(file.path, "application/octet-stream", original_filename: "bad.exe")
    post "/api/admin/releases/#{release.id}/upload", params: { file: upload }, headers: { "X-CSRF-Token" => @csrf }
    assert_response :unprocessable_entity
    assert_equal 0, ReleaseAsset.count
  ensure
    file&.close!
  end
  test "admin uploads a private installer and publishes its computed hashes" do
    release = Release.create!(version: "1.19.0", target: "win-x64")
    login
    bytes = "MZsigned-installer-test"
    file = Tempfile.new(["proser", ".exe"])
    file.write(bytes); file.flush
    stub_request(:post, "https://appwrite.example.test/v1/storage/buckets/releases/files")
      .with(headers: { "X-Appwrite-Key" => "test-storage-key" })
      .to_return(status: 201, body: "{}")
    stub_request(:get, %r{https://appwrite.example.test/v1/storage/buckets/releases/files/[a-f0-9-]+})
      .to_return(status: 200, body: { sizeOriginal: bytes.bytesize, chunksUploaded: 1, chunksTotal: 1 }.to_json)
    upload = Rack::Test::UploadedFile.new(file.path, "application/octet-stream", original_filename: "Proser-1.19.0.exe")
    post "/api/admin/releases/#{release.id}/upload", params: { file: upload }, headers: { "X-CSRF-Token" => @csrf }
    assert_response :created
    asset = release.release_assets.sole
    assert_equal Digest::SHA256.hexdigest(bytes), asset.sha256
    assert_equal Base64.strict_encode64(Digest::SHA512.digest(bytes)), asset.sha512
    post "/api/admin/releases/#{release.id}/publish", params: {}.to_json, headers: admin_headers
    assert_response :success
    assert_equal "published", release.reload.status
    assert_equal asset.sha512, release.manifest.fetch(:files).first.fetch(:sha512)
    assert_equal %w[release.upload release.publish], AuditEvent.where(subject: release.id.to_s).where("action LIKE 'release.%'").order(:id).pluck(:action)
  ensure
    file&.close!
  end
end
