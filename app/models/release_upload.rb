class ReleaseUpload < ApplicationRecord
  CHUNK_SIZE = 5.megabytes
  belongs_to :release
  belongs_to :admin_session, optional: true
  belongs_to :release_asset, optional: true
  validates :id, format: { with: /\A[a-f0-9]{32}\z/ }
  validates :total_bytes, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 2.gigabytes }
  validate do
    candidate = ReleaseAsset.new(release: release, filename: filename, size: total_bytes)
    errors.add(:filename, "Nome de arquivo inválido ou já enviado") unless candidate.valid?
  end
  validate do
    errors.add(:base, "Proprietário de upload inválido") unless ci_upload ? admin_session_id.nil? : admin_session_id.present?
  end
  after_destroy :remove_file
  def path = Rails.root.join("tmp", "release-uploads", "#{id}.part")
  def remove_file = FileUtils.rm_f(path)
  def ensure_open!
    raise Policy::Denied, "Upload expirado" if expires_at <= Time.current
    raise Policy::Denied, "Upload já concluído" if release_asset_id
    raise Policy::Denied, "Uploads permitidos apenas em rascunhos" unless release.reload.status == "draft"
  end
  def append!(offset, chunk)
    with_lock do
      ensure_open!
      raise Policy::Denied, "Parte de upload inválida" if chunk.empty? || chunk.bytesize > CHUNK_SIZE || offset < 0 || offset + chunk.bytesize > total_bytes
      FileUtils.mkdir_p(path.dirname, mode: 0700)
      if offset < received_bytes
        raise Policy::Denied, "Parte conflitante" unless File.exist?(path) && File.binread(path, chunk.bytesize, offset) == chunk
        return
      end
      raise Policy::Denied, "Posição de upload inválida" unless offset == received_bytes
      raise Policy::Denied, "Upload temporário perdido; reinicie o envio" if received_bytes.positive? && !File.exist?(path)
      File.open(path, File::RDWR | File::CREAT, 0600) do |file|
        file.binmode; file.truncate(received_bytes); file.seek(received_bytes); file.write(chunk); file.flush; file.fsync
      end
      update!(received_bytes: received_bytes + chunk.bytesize)
    end
  end
end
