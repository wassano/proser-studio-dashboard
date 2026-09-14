module Api::Admin
  class AuditController < BaseController
    def index
      render json: { items: collection(AuditEvent.order(id: :desc)), total: AuditEvent.count, page: page }
    end
  end
end
