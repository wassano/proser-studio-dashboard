class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception
  before_action { response.set_header("Cache-Control", "no-store") }
  rescue_from ActiveRecord::RecordNotFound do
    render json: { error: "Registro não encontrado" }, status: :not_found
  end
  rescue_from ActiveRecord::RecordInvalid do |error|
    render json: { error: error.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
  end
  rescue_from Policy::Denied, ActionController::ParameterMissing do |error|
    render json: { error: error.message }, status: :unprocessable_entity
  end
  rescue_from AppwriteClient::Unavailable do
    render json: { error: "Serviço de autenticação ou armazenamento indisponível" }, status: :service_unavailable
  end
  def audit(action, subject, details = {})
    AuditEvent.create!(actor: @admin&.email || "system", action: action, subject: subject.to_s, ip: request.remote_ip, details: details)
  end
  def require_admin
    token = session[:admin_token].to_s
    @admin = AdminSession.find_by(token_digest: Digest::SHA256.hexdigest(token)) if token.present?
    allowed = ENV.fetch("ADMIN_GOOGLE_EMAILS", "dwassano@gmail.com").split(",").map { |email| email.strip.downcase }
    unless @admin && @admin.expires_at > Time.current && @admin.last_seen_at > 1.hour.ago && allowed.include?(@admin.email)
      reset_session
      render json: { error: "Entre com uma conta Google autorizada" }, status: :unauthorized
      return
    end
    @admin.update_columns(last_seen_at: Time.current)
  end
  private

  # The authenticated API receives browser mutations from the one dashboard origin.
  # Rails still validates the session-bound CSRF token on every protected mutation.
  def valid_request_origin?
    return true if request.origin == ENV.fetch("DASHBOARD_URL", "http://localhost:3000")
    super
  end

end
