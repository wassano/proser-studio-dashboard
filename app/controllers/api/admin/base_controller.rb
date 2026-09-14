module Api
  module Admin
    class BaseController < ApplicationController
      before_action :require_admin
      def page = [params.fetch(:page, 1).to_i, 1].max
      def collection(scope) = scope.limit(100).offset((page - 1) * 100)
      def license_json(license)
        license.as_json.merge("plan_name" => license.plan.name, "active_devices" => license.installations.where(status: "active").count)
      end
      def installation_json(item)
        item.as_json(except: :public_key).merge("access_status" => item.access_status, "license" => item.license ? license_json(item.license) : nil)
      end
    end
  end
end
