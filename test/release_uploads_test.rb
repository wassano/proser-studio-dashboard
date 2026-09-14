require "test_helper"

class ReleaseUploadsTest < ActionDispatch::IntegrationTest
  def begin_upload(bytes)
    release = Release.create!(version: "1.19.0", target: "win-x64")
    login
    post "/api/admin/releases/#{release.id}/uploads", params: { upload: { filename: "Proser.exe", total_bytes: bytes.bytesize } }.to_json, headers: admin_headers
    assert_response :created
    item = ReleaseUpload.find(response.parsed_body.fetch("id"))
    [release, item, "/api/admin/releases/#{release.id}/uploads/#{item.id}"]
  end
  def chunk(path, bytes, offset = 0)
    put path, params: bytes, headers: admin_headers.merge("CONTENT_TYPE" => "application/octet-stream", "X-Upload-Offset" => offset.to_s)
  end
  test "chunks preserve bytes, validate order, retry safely and complete once" do
    bytes = "MZ" + "x" * ReleaseUpload::CHUNK_SIZE
    release, item, path = begin_upload(bytes)
    first = bytes.byteslice(0, ReleaseUpload::CHUNK_SIZE)
    chunk(path, first)
    assert_response :success
    chunk(path, first)
    assert_response :success
    assert_equal first.bytesize, item.reload.received_bytes
    chunk(path, "wrong", 0)
    assert_response :unprocessable_entity
    post "#{path}/complete", params: {}.to_json, headers: admin_headers
    assert_response :unprocessable_entity
    chunk(path, bytes.byteslice(first.bytesize..), first.bytesize)
    assert_response :success
    stub_request(:post, "https://appwrite.example.test/v1/storage/buckets/releases/files").to_return(status: 201, body: "{}")
    stub_request(:get, %r{https://appwrite.example.test/v1/storage/buckets/releases/files/[a-f0-9-]+})
      .to_return(status: 200, body: { sizeOriginal: bytes.bytesize, chunksUploaded: 2, chunksTotal: 2 }.to_json)
    post "#{path}/complete", params: {}.to_json, headers: admin_headers
    assert_response :created
    assert_equal Digest::SHA256.hexdigest(bytes), release.release_assets.sole.sha256
    assert_not File.exist?(item.path)
    post "#{path}/complete", params: {}.to_json, headers: admin_headers
    assert_response :success
    assert_equal 1, release.release_assets.count
    post "/api/admin/releases/#{release.id}/publish", params: {}.to_json, headers: admin_headers
    assert_response :success
  ensure
    item&.remove_file
  end
  test "upload ownership expiry size and cancellation are enforced" do
    _, item, path = begin_upload("MZtest")
    chunk(path, "MZtest", 1)
    assert_response :unprocessable_entity
    chunk(path, "x" * (ReleaseUpload::CHUNK_SIZE + 1))
    assert_response :unprocessable_entity
    item.update_columns(expires_at: 1.minute.ago)
    chunk(path, "MZtest")
    assert_response :unprocessable_entity
    item.update_columns(expires_at: 1.hour.from_now)
    login
    chunk(path, "MZtest")
    assert_response :not_found
    item.update_columns(admin_session_id: AdminSession.last.id)
    chunk(path, "MZtest")
    assert_response :success
    assert File.exist?(item.path)
    delete path, headers: admin_headers
    assert_response :no_content
    assert_not File.exist?(item.path)
  ensure
    item&.remove_file
  end
end
