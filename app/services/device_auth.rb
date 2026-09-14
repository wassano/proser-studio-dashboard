class DeviceAuth
  class Invalid < StandardError; end
  attr_reader :device_id, :nonce, :key_pem
  def initialize(request, registration: false)
    @device_id = request.headers["X-Proser-Device"].to_s
    @nonce = request.headers["X-Proser-Nonce"].to_s
    timestamp = request.headers["X-Proser-Time"].to_s
    signature = request.headers["X-Proser-Signature"].to_s
    raise Invalid unless @device_id.match?(/\A[a-f0-9]{64}\z/) && nonce.match?(/\A[a-f0-9]{32}\z/) && timestamp.match?(/\A\d{10}\z/) && signature.bytesize <= 128
    raise Invalid if (Time.current.to_i - timestamp.to_i).abs > 300
    raise Invalid unless request.query_string.empty? && request.raw_post.bytesize <= 8192
    @key_pem = registration ? JSON.parse(request.raw_post).fetch("public_key") : Installation.find_by!(device_id: device_id).public_key
    raise Invalid unless key_pem.is_a?(String) && key_pem.bytesize <= 256 && key_pem.start_with?("-----BEGIN PUBLIC KEY-----")
    key = OpenSSL::PKey.read(key_pem)
    raise Invalid unless key.oid == "ED25519" && Digest::SHA256.hexdigest(key.public_to_der) == device_id
    canonical = [request.request_method, request.path, timestamp, nonce, Digest::SHA256.hexdigest(request.raw_post)].join("\n")
    raise Invalid unless key.verify(nil, Base64.strict_decode64(signature), canonical)
    # A unique database index makes replay rejection atomic across all Rails workers.
    RequestNonce.create!(digest: Digest::SHA256.hexdigest("#{device_id}:#{nonce}"), expires_at: 10.minutes.from_now)
  rescue JSON::ParserError, KeyError, ArgumentError, OpenSSL::PKey::PKeyError, ActiveRecord::RecordNotFound, ActiveRecord::RecordNotUnique
    raise Invalid
  end
end
