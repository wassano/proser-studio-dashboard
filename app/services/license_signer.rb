require "openssl"
require "base64"

class LicenseSigner
  def self.key
    OpenSSL::PKey.read(File.binread(ENV.fetch("LICENSE_PRIVATE_KEY_PATH")))
  end
  def self.sign(payload)
    encoded = Base64.urlsafe_encode64(JSON.generate(payload), padding: false)
    kid = ENV.fetch("LICENSE_KEY_ID", "primary")
    { payload: encoded, signature: Base64.urlsafe_encode64(key.sign(nil, "proser-v1.#{kid}.#{encoded}"), padding: false), kid: kid }
  end
  def self.lease(installation, nonce)
    now = Time.current
    license = installation.license
    state = installation.access_status
    deadline = state == "active" ? [now + license.plan.offline_hours.hours, license.expires_at].compact.min : now + 5.minutes
    sign({ type: "license", schema: 1, deviceId: installation.device_id, nonce: nonce,
      status: state, issuedAt: now.to_i, expiresAt: deadline.to_i,
      licenseId: license&.id&.to_s, licenseExpiresAt: license&.expires_at&.to_i,
      features: state == "active" ? license.effective_features : {},
      limits: state == "active" ? license.effective_limits : {}, minimumVersion: license&.minimum_version,
      message: { "pending" => "Limite geral atingido ou registro pausado. Aguarde a liberação pelo administrador.", "rejected" => "Registro recusado pelo administrador.", "revoked" => "Instalação revogada.", "blocked" => "Licença suspensa, revogada ou expirada.", "upgrade_required" => "Atualize o Proser para continuar." }[state] })
  end
end
