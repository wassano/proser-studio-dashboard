class Release < ApplicationRecord
  has_many :release_assets, dependent: :restrict_with_exception
  validates :version, format: { with: /\A\d+\.\d+\.\d+\z/ }, uniqueness: { scope: %i[target channel] }
  validates :target, inclusion: { in: %w[win-x64 win7-x64 mac-arm64 mac-x64] }
  validates :channel, inclusion: { in: %w[stable beta] }
  validates :status, inclusion: { in: %w[draft published withdrawn] }
  validates :notes, length: { maximum: 10000 }
  def ci_managed? = ci_expected_assets.present?
  def verify_ci_assets!
    actual = release_assets.map { |a| { "filename" => a.filename, "size" => a.size, "sha256" => a.sha256 } }.sort_by { |a| a["filename"] }
    raise Policy::Denied, "Arquivos do CI incompletos ou divergentes" unless ci_managed? && actual == ci_expected_assets.sort_by { |a| a["filename"] }
  end
  def update_asset
    extension = target.start_with?("mac-") ? ".zip" : ".exe"
    release_assets.find { |asset| File.extname(asset.filename) == extension }
  end
  def publish!
    with_lock do
      raise Policy::Denied, "A versão deve estar em rascunho" unless status == "draft"
      if ci_managed?
        raise Policy::Denied, "Aguarde a conclusão do envio pelo CI" unless ci_ready
        verify_ci_assets!
      end
      expected = target.start_with?("mac-") ? ".zip" : ".exe"
      raise Policy::Denied, "Envie exatamente um instalador #{expected}" unless release_assets.count { |a| File.extname(a.filename) == expected } == 1
      previous = self.class.where(target: target, channel: channel).where.not(published_at: nil).where.not(id: id).pluck(:version)
      raise Policy::Denied, "A versão deve ser superior às já publicadas" if previous.any? { |v| Gem::Version.new(v) >= Gem::Version.new(version) }
      update!(status: "published", published_at: Time.current)
    end
  end
  def manifest
    asset = update_asset or raise Policy::Denied, "Instalador indisponível"
    { version: version, releaseDate: published_at.iso8601, files: [{ url: "files/#{asset.id}/#{ERB::Util.url_encode(asset.filename)}", sha512: asset.sha512, size: asset.size }], path: "files/#{asset.id}/#{ERB::Util.url_encode(asset.filename)}", sha512: asset.sha512 }
  end
end
