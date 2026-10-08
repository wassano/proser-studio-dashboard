module CiAuthentication
  extend ActiveSupport::Concern
  included do
    skip_before_action :verify_authenticity_token
    before_action :authenticate_ci
  end
  def authenticate_ci
    expected = ENV["RELEASE_CI_TOKEN"].to_s
    supplied = request.authorization.to_s.delete_prefix("Bearer ")
    unless expected.match?(/\A[a-f0-9]{64}\z/) && ActiveSupport::SecurityUtils.secure_compare(expected, supplied)
      render json: { error: "Credencial de CI inválida" }, status: :unauthorized
    end
  end
  def audit(action, subject, details = {})
    AuditEvent.create!(actor: "github-actions", action: action, subject: subject.to_s, ip: request.remote_ip, details: details)
  end
end
