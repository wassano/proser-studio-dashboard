require "test_helper"

class AdminReleaseDownloadsTest < ActionDispatch::IntegrationTest
  def installer(release, filename)
    bytes = "installer-content-#{filename}"
    release.release_assets.create!(filename: filename, size: bytes.bytesize, storage_id: SecureRandom.uuid,
      sha256: Digest::SHA256.hexdigest(bytes), sha512: Base64.strict_encode64(Digest::SHA512.digest(bytes)))
  end
  def download_path(release, asset)
    "/api/admin/releases/#{release.id}/files/#{asset.id}/#{ERB::Util.url_encode(asset.filename)}"
  end
  test "draft downloads require an administrator and remain unavailable publicly" do
    release = Release.create!(version: "1.21.5", target: "win-x64")
    asset = installer(release, "Proser studio Setup 1.21.5.exe")
    get download_path(release, asset)
    assert_response :unauthorized
    get download_path(release, asset).sub("/api/admin/", "/api/v1/")
    assert_response :not_found
    assert_not_requested :get, "https://appwrite.example.test/v1/storage/buckets/releases/files/#{asset.storage_id}/download"
    assert_equal "draft", release.reload.status
    assert_nil release.published_at
  end
  test "authenticated downloads stream installers and update packages in every release status" do
    release = Release.create!(version: "1.21.5", target: "mac-arm64")
    assets = %w[dmg zip].map { |ext| installer(release, "Proser studio 1.21.5.#{ext}") }
    login
    %w[draft published withdrawn].each do |status|
      release.update!(status: status)
      assets.each do |asset|
        bytes = "installer-content-#{asset.filename}"
        stub_request(:get, "https://appwrite.example.test/v1/storage/buckets/releases/files/#{asset.storage_id}/download")
          .with(headers: { "X-Appwrite-Key" => "test-storage-key" }).to_return(status: 200, body: bytes)
        get download_path(release, asset)
        assert_response :success
        assert_equal bytes, response.body
        assert_equal bytes.bytesize.to_s, response.headers["Content-Length"]
        assert_equal "application/octet-stream", response.headers["Content-Type"]
        assert_match "attachment", response.headers["Content-Disposition"]
        assert_equal "no-store", response.headers["Cache-Control"]
        assert_equal status, release.reload.status
        assert_nil release.published_at
        assert_not response.body.include?("test-storage-key")
      end
    end
  end
  test "downloads validate the filename and scope the asset to its release" do
    release = Release.create!(version: "1.21.5", target: "win-x64")
    other = Release.create!(version: "1.21.6", target: "win-x64")
    asset = installer(release, "Proser.exe")
    other_asset = installer(other, "Proser.exe")
    login
    get download_path(release, asset).sub("Proser.exe", "wrong.exe")
    assert_response :not_found
    get download_path(release, other_asset)
    assert_response :not_found
    assert_not_requested :get, %r{https://appwrite.example.test/v1/storage/buckets/releases/files/.*/download}
  end
end
