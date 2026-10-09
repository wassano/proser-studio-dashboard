module Api::Ci
  class ReleasesController < ApplicationController
    include CiAuthentication
    def create
      input = params.require(:release).permit(:version, :target, :channel, :notes, :ci_run_url, assets: %i[filename size sha256]).to_h
      assets = input.delete("assets")
      raise Policy::Denied, "Manifesto de arquivos inválido" unless assets.is_a?(Array) && assets.size.between?(1, 8)
      assets.each do |asset|
        candidate = ReleaseAsset.new(filename: asset["filename"], size: asset["size"])
        candidate.valid?
        raise Policy::Denied, "Manifesto de arquivos inválido" if candidate.errors[:filename].any? || candidate.errors[:size].any? || !asset["size"].is_a?(Integer) || !asset["sha256"].to_s.match?(/\A[a-f0-9]{64}\z/)
      end
      raise Policy::Denied, "Arquivos duplicados" unless assets.map { |a| a["filename"] }.uniq.size == assets.size
      required = input["target"].to_s.start_with?("mac-") ? %w[.dmg .zip] : %w[.exe]
      raise Policy::Denied, "Envie somente instaladores e pacotes de atualização" unless assets.size == required.size
      raise Policy::Denied, "Instaladores obrigatórios ausentes ou duplicados" unless required.all? { |ext| assets.count { |a| File.extname(a["filename"]) == ext } == 1 }
      raise Policy::Denied, "Origem do CI inválida" unless input["ci_run_url"].to_s.match?(%r{\Ahttps://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/actions/runs/\d+\z})
      release = nil
      RegistrationSetting.current.with_lock do
        release = Release.find_or_initialize_by(input.slice("version", "target", "channel"))
        if release.persisted?
          raise Policy::Denied, "Versão existente diverge do CI" unless release.ci_expected_assets.sort_by { |a| a["filename"] } == assets.sort_by { |a| a["filename"] }
          raise Policy::Denied, "Versão retirada" if release.status == "withdrawn"
        else
          release.assign_attributes(input.merge("ci_expected_assets" => assets))
          release.save!
          audit("release.ci.create", release.id, run_url: release.ci_run_url)
        end
      end
      render json: release.as_json(include: :release_assets), status: :ok
    end
    def complete
      release = Release.find(params[:id])
      release.with_lock do
        release.verify_ci_assets!
        raise Policy::Denied, "Versão retirada" if release.status == "withdrawn"
        unless release.ci_ready
          release.update!(ci_ready: true)
          audit("release.ci.ready", release.id, run_url: release.ci_run_url)
        end
      end
      render json: release.as_json(include: :release_assets)
    end
  end
end
