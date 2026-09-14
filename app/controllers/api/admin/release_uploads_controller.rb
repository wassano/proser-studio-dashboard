module Api::Admin
  class ReleaseUploadsController < BaseController
    def create
      release = Release.find(params[:release_id])
      @admin.with_lock do
        raise Policy::Denied, "Há dois envios pendentes. Conclua ou cancele antes de iniciar outro." if ReleaseUpload.where(admin_session: @admin, release_asset_id: nil).where("expires_at > ?", Time.current).count >= 2
        release.with_lock do
          raise Policy::Denied, "Uploads permitidos apenas em rascunhos" unless release.status == "draft"
          input = params.require(:upload).permit(:filename, :total_bytes)
          item = ReleaseUpload.create!(input.merge(id: SecureRandom.hex(16), release: release, admin_session: @admin, expires_at: 4.hours.from_now))
          render json: { id: item.id, chunk_size: ReleaseUpload::CHUNK_SIZE }, status: :created
        end
      end
    end
    def update
      item = owned_upload
      raw_offset = request.headers["X-Upload-Offset"].to_s
      raise Policy::Denied, "Posição de upload inválida" unless raw_offset.match?(/\A\d{1,12}\z/)
      chunk = request.body.read(ReleaseUpload::CHUNK_SIZE + 1)
      item.append!(raw_offset.to_i, chunk)
      render json: { received_bytes: item.received_bytes }
    end
    def complete
      item = owned_upload
      item.with_lock do
        if item.release_asset_id
          render json: item.release_asset
          return
        end
        item.ensure_open!
        raise Policy::Denied, "Arquivo incompleto" unless item.received_bytes == item.total_bytes && File.exist?(item.path) && File.size(item.path) == item.total_bytes
        asset = File.open(item.path, "rb") do |file|
          ReleaseStorage.call(item.release, file, item.filename) do |stored|
            item.update_columns(release_asset_id: stored.id, updated_at: Time.current)
            audit("release.upload", item.release_id, filename: stored.filename, sha256: stored.sha256, size: stored.size)
          end
        end
        render json: asset, status: :created
      end
      item.remove_file
    end
    def destroy
      item = owned_upload
      item.with_lock { item.destroy! }
      head :no_content
    end
    private
    def owned_upload
      ReleaseUpload.find_by!(id: params[:id], release_id: params[:release_id], admin_session_id: @admin.id)
    end
  end
end
