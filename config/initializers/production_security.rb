if Rails.env.production?
  required = %w[DASHBOARD_URL API_URL ADMIN_GOOGLE_EMAILS SECRET_KEY_BASE DATABASE_URL REDIS_URL APPWRITE_ENDPOINT APPWRITE_PROJECT_ID APPWRITE_AUTH_KEY APPWRITE_STORAGE_KEY APPWRITE_RELEASE_BUCKET LICENSE_PRIVATE_KEY_PATH TRUSTED_PROXY_CIDRS]
  missing = required.select { |name| ENV[name].blank? || ENV[name].include?("CHANGE_ME") }
  raise "Configuração de produção incompleta: #{missing.join(', ')}" if missing.any?
  %w[DASHBOARD_URL API_URL APPWRITE_ENDPOINT].each do |name|
    uri = URI(ENV.fetch(name))
    raise "#{name} exige HTTPS sem credenciais na URL" unless uri.scheme == "https" && uri.host && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil?
  end
  raise "URLs públicas exigem apenas a origem" unless %w[DASHBOARD_URL API_URL].all? { |name| URI(ENV.fetch(name)).path.in?(["", "/"]) }
  raise "SECRET_KEY_BASE muito curta" if ENV.fetch("SECRET_KEY_BASE").bytesize < 64
  token = ENV["WORKER_ORIGIN_TOKEN"].to_s
  raise "WORKER_ORIGIN_TOKEN deve ter 64 caracteres hexadecimais" if token.present? && !token.match?(/\A[a-f0-9]{64}\z/)
  key = OpenSSL::PKey.read(File.read(ENV.fetch("LICENSE_PRIVATE_KEY_PATH")))
  raise "A assinatura exige uma chave privada Ed25519" unless key.oid == "ED25519"
  key.sign(nil, "proser-boot-check")
end
