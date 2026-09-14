module Api::Admin
  class InstallationsController < BaseController
    def index
      scope = Installation.includes(license: :plan).order(last_seen_at: :desc, id: :desc)
      scope = scope.where(status: params[:status]) if %w[pending active rejected revoked].include?(params[:status])
      if params[:q].present?
        term = "%#{Installation.sanitize_sql_like(params[:q].to_s.first(100))}%"
        scope = scope.where("computer_name LIKE ? OR last_ip LIKE ? OR device_id LIKE ?", term, term, term)
      end
      render json: { items: collection(scope).map { |item| installation_json(item) }, total: scope.count, page: page }
    end
    def update
      item = Installation.find(params[:id])
      status = params.require(:installation).require(:status)
      raise Policy::Denied, "Use a aprovação para liberar uma instalação" unless %w[rejected revoked].include?(status)
      RegistrationSetting.current.with_lock do
        item.with_lock { item.update!(status: status); audit("installation.#{status}", item.id) }
      end
      render json: installation_json(item)
    end
    def approve
      item = Installation.find(params[:id])
      RegistrationSetting.current.with_lock do
        settings = RegistrationSetting.current
        if item.reload.status != "active" && Installation.where(status: "active").count >= settings.installation_limit
          raise Policy::Denied, "Limite global de instalações atingido"
        end
        license = params[:license_id].present? ? License.find(params[:license_id]) : item.license
        license ||= License.create!(plan: settings.plan, name: item.computer_name)
        item.approve!(license)
        audit("installation.approve", item.id, license_id: license.id)
      end
      render json: installation_json(item)
    end
  end
end
