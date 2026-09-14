module Api::Admin
  class PlansController < BaseController
    def index
      render json: { items: Plan.order(:id), features: Plan::FEATURES, limits: Plan::LIMITS }
    end
    def create
      plan = Plan.new(plan_params)
      Plan.transaction { plan.save!; audit("plan.create", plan.id) }
      render json: plan, status: :created
    end
    def update
      plan = Plan.find(params[:id])
      plan.with_lock { plan.update!(plan_params); audit("plan.update", plan.id, plan.previous_changes.except("updated_at")) }
      render json: plan
    end
    private
    def plan_params = params.require(:plan).permit(:name, :offline_hours, features: {}, limits: {})
  end
end
