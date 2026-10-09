module Api::V1
  class ReleasesController < ApplicationController
    def index
      releases = Release.includes(:release_assets).where(status: "published", channel: "stable").to_a
      latest = releases.group_by(&:target).values.map { |items| items.max_by { |item| Gem::Version.new(item.version) } }
      render json: { items: latest.sort_by(&:target).map { |item| {
        id: item.id, version: item.version, target: item.target, notes: item.notes, published_at: item.published_at,
        assets: item.release_assets.select { |a| File.extname(a.filename) == (item.target.start_with?("mac-") ? ".dmg" : ".exe") }.map { |a| {
          id: a.id, filename: a.filename, size: a.size, sha256: a.sha256,
          download_path: "/api/v1/releases/#{item.id}/files/#{a.id}/#{ERB::Util.url_encode(a.filename)}"
        } }
      } } }
    end
    def download
      release = Release.where(status: "published").find(params[:release_id])
      asset = release.release_assets.find(params[:id])
      return head :not_found unless params[:filename] == asset.filename
      response.headers["Content-Type"] = "application/octet-stream"
      response.headers["Content-Length"] = asset.size.to_s
      response.headers["Content-Disposition"] = ActionDispatch::Http::ContentDisposition.format(disposition: "attachment", filename: asset.filename)
      self.response_body = AppwriteClient.new(storage: true).stream(asset.storage_id)
    end
  end
end
