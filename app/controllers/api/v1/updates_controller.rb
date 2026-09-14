module Api::V1
  class UpdatesController < ActionController::API
    before_action :authorize_download
    def metadata
      expected = @release.target.start_with?("mac-") ? "latest-mac.yml" : "latest.yml"
      return head :not_found unless params[:metadata] == expected
      render plain: JSON.parse(JSON.generate(@release.manifest)).to_yaml, content_type: "application/yaml"
    end
    def download
      asset = @release.release_assets.find(params[:id])
      return head :not_found unless params[:filename] == asset.filename
      # Differential downloads are disabled in the client; stream complete immutable files.
      response.headers["Content-Type"] = "application/octet-stream"
      response.headers["Content-Length"] = asset.size.to_s
      response.headers["Content-Disposition"] = ActionDispatch::Http::ContentDisposition.format(disposition: "attachment", filename: asset.filename)
      self.response_body = AppwriteClient.new(storage: true).stream(asset.storage_id)
    end
    private
    def authorize_download
      response.set_header("Cache-Control", "no-store")
      token = request.authorization.to_s.delete_prefix("Bearer ")
      grant = DownloadGrant.includes(:release, installation: { license: :plan }).find_by(token_digest: Digest::SHA256.hexdigest(token)) if token.match?(/\A[a-f0-9]{64}\z/)
      unless grant && grant.expires_at > Time.current && grant.release_id.to_s == params[:release_id] && grant.release.status == "published" && %w[active upgrade_required].include?(grant.installation.access_status)
        head :unauthorized
        return
      end
      @release = grant.release
    end
  end
end
