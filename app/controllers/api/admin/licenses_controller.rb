module Api::Admin
  class LicensesController < BaseController
    def index
      scope = License.includes(:plan).order(id: :desc)
      if params[:q].present?
        scope = scope.where("name LIKE ?", "%#{License.sanitize_sql_like(params[:q].to_s.first(100))}%")
      end
      render json: { items: collection(scope).map { |item| license_json(item) }, total: scope.count, page: page }
    end
    def create
      license = License.new(license_params)
      License.transaction { license.save!; audit("license.create", license.id) }
      render json: license_json(license), status: :created
    end
    def update
      license = License.find(params[:id])
      license.with_lock { license.update!(license_params); audit("license.update", license.id, license.previous_changes.except("updated_at")) }
      render json: license_json(license)
    end
    private
    def license_params
      params.require(:license).permit(:name, :plan_id, :max_devices, :expires_at, :status, :channel, :minimum_version, feature_overrides: {}, limit_overrides: {})
    end
  end
end
