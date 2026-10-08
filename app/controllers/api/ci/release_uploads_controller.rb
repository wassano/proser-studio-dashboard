module Api::Ci
  class ReleaseUploadsController < Api::Admin::ReleaseUploadsController
    skip_before_action :require_admin
    include CiAuthentication
    def create
      release = Release.find(params[:release_id])
      release.with_lock do
        raise Policy::Denied, "Uploads permitidos apenas em rascunhos do CI" unless release.status == "draft" && release.ci_managed? && !release.ci_ready
        input = params.require(:upload).permit(:filename, :total_bytes)
        expected = release.ci_expected_assets.find { |a| a["filename"] == input[:filename] && a["size"] == input[:total_bytes] }
        raise Policy::Denied, "Arquivo não previsto pelo CI" unless expected
        # Reuse a pending upload after an interrupted job; completed assets are returned by release.create.
        item = release_upload_scope.where(filename: input[:filename], release_asset_id: nil).where("expires_at > ?", Time.current).first
        item ||= ReleaseUpload.create!(input.merge(id: SecureRandom.hex(16), release: release, ci_upload: true, expires_at: 4.hours.from_now))
        render json: { id: item.id, chunk_size: ReleaseUpload::CHUNK_SIZE, received_bytes: item.received_bytes }, status: :created
      end
    end
    private
    def release_upload_scope = ReleaseUpload.where(release_id: params[:release_id], ci_upload: true)
    def owned_upload = release_upload_scope.find(params[:id])
  end
end
