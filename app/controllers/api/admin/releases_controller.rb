module Api::Admin
  class ReleasesController < BaseController
    def index
      scope = Release.includes(:release_assets).order(id: :desc)
      render json: { items: collection(scope).as_json(include: :release_assets), total: scope.count, page: page }
    end
    def create
      release = Release.new(params.require(:release).permit(:version, :target, :channel, :notes))
      Release.transaction { release.save!; audit("release.create", release.id) }
      render json: release, status: :created
    end
    def download
      release = Release.find(params[:release_id])
      asset = release.release_assets.find(params[:id])
      return head :not_found unless params[:filename] == asset.filename
      response.headers["Content-Type"] = "application/octet-stream"
      response.headers["Content-Length"] = asset.size.to_s
      response.headers["Content-Disposition"] = ActionDispatch::Http::ContentDisposition.format(disposition: "attachment", filename: asset.filename)
      self.response_body = AppwriteClient.new(storage: true).stream(asset.storage_id)
    end
    def upload
      release = Release.find(params[:id])
      file = params.require(:file)
      raise Policy::Denied, "Selecione um instalador válido" unless file.is_a?(ActionDispatch::Http::UploadedFile)
      asset = ReleaseStorage.call(release, file.tempfile, file.original_filename) do |stored|
        audit("release.upload", release.id, filename: stored.filename, sha256: stored.sha256, size: stored.size)
      end
      render json: asset, status: :created
    end
    def publish
      release = Release.find(params[:id])
      # The same admission lock also serializes publication of competing versions.
      RegistrationSetting.current.with_lock { release.publish!; audit("release.publish", release.id, version: release.version, target: release.target) }
      render json: release
    end
    def withdraw
      release = Release.find(params[:id])
      release.with_lock { release.update!(status: "withdrawn"); audit("release.withdraw", release.id) }
      render json: release
    end
  end
end
