class ReleaseStorage
  def self.call(release, file, filename)
    asset = release.release_assets.build(filename: filename, size: file.size, storage_id: SecureRandom.uuid)
    raise Policy::Denied, asset.errors.full_messages.join(", ") unless asset.valid?
    file.rewind
    magic = file.read(4).to_s
    file.rewind
    extension = File.extname(asset.filename)
    raise Policy::Denied, "Conteúdo do instalador inválido" if (extension == ".exe" && !magic.start_with?("MZ")) || (extension == ".zip" && !magic.start_with?("PK"))
    storage = AppwriteClient.new(storage: true)
    begin
      release.with_lock do
        raise Policy::Denied, "Uploads permitidos apenas em rascunhos" unless release.status == "draft"
        asset.sha512 = Base64.strict_encode64(Digest::SHA512.file(file.path).digest)
        asset.sha256 = Digest::SHA256.file(file.path).hexdigest
        if release.ci_managed?
          expected = { "filename" => asset.filename, "size" => asset.size, "sha256" => asset.sha256 }
          raise Policy::Denied, "Arquivo diverge do manifesto do CI" unless release.ci_expected_assets.include?(expected)
        end
        upload_attempted = true
        storage.upload(file, asset.filename, asset.storage_id)
        asset.save!
        yield asset if block_given?
      end
    rescue StandardError
      storage.delete_file(asset.storage_id) rescue nil if upload_attempted
      raise
    end
    asset
  end
end
