module Api::V1
  class DevicesController < ActionController::API
    before_action :authenticate_device
    rescue_from DeviceAuth::Invalid do
      render json: { error: "Solicitação inválida ou expirada" }, status: :unauthorized
    end
    rescue_from ActiveRecord::RecordInvalid, Policy::Denied do
      render json: { error: "Registro inválido ou indisponível" }, status: :unprocessable_entity
    end
    def register
      installation = Registration.call(@auth, metadata.to_h.symbolize_keys, request.remote_ip)
      render json: LicenseSigner.lease(installation, @auth.nonce)
    end
    def heartbeat
      installation = Installation.find_by!(device_id: @auth.device_id)
      installation.with_lock do
        # A target is fixed on registration; changing it requires another installation identity.
        values = metadata.to_h.except("target")
        installation.update!(values.merge(last_ip: request.remote_ip, location: GeoLocation.lookup(request.remote_ip), last_seen_at: Time.current))
      end
      render json: LicenseSigner.lease(installation, @auth.nonce)
    end
    def update_check
      installation = Installation.find_by!(device_id: @auth.device_id)
      descriptor = nil
      if %w[active upgrade_required].include?(installation.access_status)
        release = Release.where(target: installation.target, channel: installation.license.channel, status: "published").max_by { |item| Gem::Version.new(item.version) }
        if release && Gem::Version.new(release.version) > Gem::Version.new(installation.app_version)
          token = SecureRandom.hex(32)
          DownloadGrant.create!(installation: installation, release: release, token_digest: Digest::SHA256.hexdigest(token), expires_at: 2.hours.from_now)
          descriptor = { id: release.id.to_s, target: release.target, token: token, manifest: release.manifest }
        end
      end
      render json: LicenseSigner.sign({ type: "update", schema: 1, deviceId: installation.device_id, nonce: @auth.nonce, issuedAt: Time.current.to_i, expiresAt: 2.hours.from_now.to_i, release: descriptor })
    end
    private
    def authenticate_device
      response.set_header("Cache-Control", "no-store")
      raise DeviceAuth::Invalid unless request.media_type == "application/json"
      @auth = DeviceAuth.new(request, registration: action_name == "register")
    end
    def metadata
      params.permit(:computer_name, :os, :arch, :app_version, :target)
    end
  end
end
