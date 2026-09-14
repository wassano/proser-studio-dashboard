module Api::Admin
  class SettingsController < BaseController
    def show
      render json: RegistrationSetting.current.as_json.merge(active_installations: Installation.where(status: "active").count)
    end
    def update
      settings = RegistrationSetting.current
      settings.with_lock do
        settings.update!(params.require(:settings).permit(:installation_limit, :registration_enabled, :plan_id))
        audit("settings.update", settings.id, settings.previous_changes.except("updated_at"))
      end
      show
    end
  end
end
