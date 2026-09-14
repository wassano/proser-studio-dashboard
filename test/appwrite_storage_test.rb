require "test_helper"

class AppwriteStorageTest < ActiveSupport::TestCase
  test "large installers use bounded chunks and final size verification" do
    file = Tempfile.new("proser-installer")
    bytes = 5 * 1024 * 1024
    file.write("MZ" + "x" * bytes); file.flush
    endpoint = "https://appwrite.example.test/v1/storage/buckets/releases/files"
    first = stub_request(:post, endpoint).with(headers: { "Content-Range" => "bytes 0-#{bytes - 1}/#{bytes + 2}", "X-Appwrite-Key" => "test-storage-key" }).to_return(status: 201, body: '{}')
    last = stub_request(:post, endpoint).with(headers: { "Content-Range" => "bytes #{bytes}-#{bytes + 1}/#{bytes + 2}", "X-Appwrite-ID" => "installer" }).to_return(status: 201, body: '{}')
    stub_request(:get, "#{endpoint}/installer").to_return(status: 200, body: { sizeOriginal: bytes + 2, chunksUploaded: 2, chunksTotal: 2 }.to_json)
    assert_equal "installer", AppwriteClient.new(storage: true).upload(file, "Proser.exe", "installer")
    assert_requested(first, times: 1)
    assert_requested(last, times: 1)
  ensure
    file&.close!
  end
end
