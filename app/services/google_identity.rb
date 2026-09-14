class GoogleIdentity
  # Appwrite's SSR token exchange does not retain provider details on the session.
  # Verify the linked Google identity against Google itself instead of trusting a client email.
  def self.verified?(client, email)
    identity = client.identities.find { |item| item["provider"] == "google" && item["providerEmail"].to_s.downcase == email }
    return false unless identity && identity["providerAccessToken"].present?
    uri = URI("https://openidconnect.googleapis.com/v1/userinfo")
    req = Net::HTTP::Get.new(uri, "Authorization" => "Bearer #{identity.fetch('providerAccessToken')}")
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 10) { |http| http.request(req) }
    return false unless response.is_a?(Net::HTTPSuccess)
    info = JSON.parse(response.body)
    info["email_verified"] == true && info["email"].to_s.downcase == email && info["sub"] == identity["providerUid"]
  rescue IOError, SystemCallError, Timeout::Error, JSON::ParserError, OpenSSL::SSL::SSLError
    false
  end
end
