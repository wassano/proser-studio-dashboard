class SessionsController < ApplicationController
  before_action :require_admin, only: :destroy
  def show
    require_admin
    return if performed?
    render json: { email: @admin.email, csrf_token: form_authenticity_token }
  end
  def start
    reset_session
    state = SecureRandom.hex(32)
    session[:oauth_state] = state
    session[:oauth_started_at] = Time.current.to_i
    origin = ENV.fetch("API_URL", ENV.fetch("DASHBOARD_URL", "http://localhost:3000"))
    redirect_to AppwriteClient.new.oauth_url(success: "#{origin}/auth/callback?state=#{state}", failure: "#{origin}/auth/failure"), allow_other_host: true
  end
  def callback
    state = session.delete(:oauth_state).to_s
    started = session.delete(:oauth_started_at).to_i
    raise Policy::Denied, "Login expirado. Tente novamente." unless state.bytesize == 64 && ActiveSupport::SecurityUtils.secure_compare(state, params[:state].to_s) && started > 10.minutes.ago.to_i
    raise Policy::Denied, "Retorno de login inválido" unless params[:userId].to_s.bytesize.between?(1, 36) && params[:secret].to_s.bytesize.between?(1, 2048)
    created = AppwriteClient.new.create_session(params[:userId], params[:secret])
    client = AppwriteClient.new(session: created.fetch("secret"))
    begin
      account = client.account
      allowed = ENV.fetch("ADMIN_GOOGLE_EMAILS", "dwassano@gmail.com").split(",").map { |email| email.strip.downcase }
      email = account.fetch("email").downcase
      raise Policy::Denied, "Conta Google não autorizada" unless account["emailVerification"] == true && account["status"] == true && allowed.include?(email) && GoogleIdentity.verified?(client, email)
      reset_session
      token = SecureRandom.hex(32)
      @admin = AdminSession.create!(token_digest: Digest::SHA256.hexdigest(token), email: email, expires_at: 8.hours.from_now, last_seen_at: Time.current)
      session[:admin_token] = token
      audit("admin.login", @admin.id)
    ensure
      # The panel keeps only its own revocable session; no Appwrite/Google token reaches React.
      client.delete_session
    end
    redirect_to ENV.fetch("DASHBOARD_URL", "http://localhost:3000"), allow_other_host: true
  end
  def failure
    reset_session
    redirect_to "#{ENV.fetch("DASHBOARD_URL", "http://localhost:3000")}/?login=failed", allow_other_host: true
  end
  def destroy
    audit("admin.logout", @admin.id)
    @admin.destroy!
    reset_session
    head :no_content
  end
end
