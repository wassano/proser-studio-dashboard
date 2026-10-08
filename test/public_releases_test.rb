require "test_helper"

class PublicReleasesTest < ActionDispatch::IntegrationTest
  def release(version, target: "win-x64", channel: "stable", published: true)
    item = Release.create!(version: version, target: target, channel: channel)
    bytes = "MZpublic-installer"
    item.release_assets.create!(filename: "Proser #{version}.exe", size: bytes.bytesize, storage_id: SecureRandom.uuid, sha256: Digest::SHA256.hexdigest(bytes), sha512: Base64.strict_encode64(Digest::SHA512.digest(bytes)))
    item.publish! if published
    item
  end
  test "public catalog selects latest stable per target and hides drafts and storage credentials" do
    release("1.20.0")
    latest = release("1.21.0")
    release("1.22.0", published: false)
    release("1.23.0", channel: "beta")
    get "/api/v1/releases"
    assert_response :success
    assert_equal [latest.id], response.parsed_body.fetch("items").map { |item| item.fetch("id") }
    assert_not response.body.include?("storage_id")
    assert_not response.body.include?("test-storage-key")
    assert_equal Digest::SHA256.hexdigest("MZpublic-installer"), response.parsed_body.dig("items", 0, "assets", 0, "sha256")
  end
  test "public links stream published files without login and stop working on withdrawal" do
    item = release("1.21.0")
    asset = item.release_assets.sole
    path = "/api/v1/releases/#{item.id}/files/#{asset.id}/#{ERB::Util.url_encode(asset.filename)}"
    stub_request(:get, "https://appwrite.example.test/v1/storage/buckets/releases/files/#{asset.storage_id}/download").to_return(status: 200, body: "MZpublic-installer")
    get path
    assert_response :success
    assert_equal "MZpublic-installer", response.body
    assert_match "attachment", response.headers["Content-Disposition"]
    assert_equal "no-store", response.headers["Cache-Control"]
    get path.sub(ERB::Util.url_encode(asset.filename), "wrong.exe")
    assert_response :not_found
    item.update!(status: "withdrawn")
    get path
    assert_response :not_found
    draft = release("1.22.0", published: false)
    get "/api/v1/releases/#{draft.id}/files/#{draft.release_assets.sole.id}/Proser.exe"
    assert_response :not_found
  end
end
