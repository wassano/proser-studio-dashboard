require "net/http"
require "uri"
require "stringio"

class AppwriteClient
  class Unavailable < StandardError; end
  def initialize(session: nil, storage: false)
    @session = session
    @storage = storage
  end
  def endpoint = ENV.fetch("APPWRITE_ENDPOINT")
  def headers
    result = { "X-Appwrite-Project" => ENV.fetch("APPWRITE_PROJECT_ID") }
    if @session
      result["X-Appwrite-Session"] = @session
    else
      result["X-Appwrite-Key"] = ENV.fetch(@storage ? "APPWRITE_STORAGE_KEY" : "APPWRITE_AUTH_KEY")
    end
    result
  end
  def http(uri)
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 120, write_timeout: 120) { |connection| yield connection }
  end
  def request(method, path, body: nil)
    uri = URI("#{endpoint}#{path}")
    req = Net::HTTP.const_get(method.to_s.capitalize).new(uri, headers.merge("Content-Type" => "application/json"))
    req.body = JSON.generate(body) if body
    response = http(uri) { |connection| connection.request(req) }
    raise Unavailable, "Appwrite indisponível (#{response.code})" unless response.is_a?(Net::HTTPSuccess)
    response.body.to_s.empty? ? {} : JSON.parse(response.body)
  rescue IOError, SystemCallError, Timeout::Error, JSON::ParserError, OpenSSL::SSL::SSLError
    raise Unavailable, "Não foi possível acessar o Appwrite"
  end
  def oauth_url(success:, failure:)
    uri = URI("#{endpoint}/account/tokens/oauth2/google")
    uri.query = URI.encode_www_form(project: ENV.fetch("APPWRITE_PROJECT_ID"), success: success, failure: failure)
    uri.to_s
  end
  def create_session(user_id, secret) = request(:post, "/account/sessions/token", body: { userId: user_id, secret: secret })
  def account = request(:get, "/account")
  def current_session = request(:get, "/account/sessions/current")
  def identities = request(:get, "/account/identities").fetch("identities")
  def delete_session = request(:delete, "/account/sessions/current")
  def bucket_path = "/storage/buckets/#{ENV.fetch('APPWRITE_RELEASE_BUCKET')}"
  def upload(file, filename, storage_id)
    uri = URI("#{endpoint}#{bucket_path}/files")
    file.rewind
    offset = 0
    total = file.size
    while (chunk = file.read(5 * 1024 * 1024))
      req = Net::HTTP::Post.new(uri, headers)
      req["Content-Range"] = "bytes #{offset}-#{offset + chunk.bytesize - 1}/#{total}"
      req["X-Appwrite-ID"] = storage_id if offset.positive?
      req.set_form([["fileId", storage_id], ["file", StringIO.new(chunk), { filename: filename, content_type: "application/octet-stream" }]], "multipart/form-data")
      response = http(uri) { |connection| connection.request(req) }
      raise Unavailable, "Falha ao armazenar o instalador" unless response.is_a?(Net::HTTPSuccess)
      offset += chunk.bytesize
    end
    info = request(:get, "#{bucket_path}/files/#{storage_id}")
    raise Unavailable, "Upload incompleto" unless info.fetch("sizeOriginal") == total && info.fetch("chunksUploaded") == info.fetch("chunksTotal")
    storage_id
  end
  def delete_file(id) = request(:delete, "#{bucket_path}/files/#{id}")
  def stream(id)
    Enumerator.new do |stream|
      uri = URI("#{endpoint}#{bucket_path}/files/#{id}/download")
      http(uri) do |connection|
        connection.request(Net::HTTP::Get.new(uri, headers)) do |response|
          raise Unavailable, "Instalador indisponível" unless response.is_a?(Net::HTTPSuccess)
          response.read_body { |chunk| stream << chunk }
        end
      end
    end
  end
end
