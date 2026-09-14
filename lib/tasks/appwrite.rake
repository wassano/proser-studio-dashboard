namespace :proser do
  desc "Provisiona o bucket privado de versões no Appwrite já configurado"
  task provision_storage: :environment do
    client = AppwriteClient.new(storage: true)
    id = ENV.fetch("APPWRITE_RELEASE_BUCKET")
    body = { bucketId: id, name: "Proser Releases", permissions: [], fileSecurity: true, enabled: true, maximumFileSize: 2.gigabytes, allowedFileExtensions: %w[exe zip dmg blockmap], compression: "none", encryption: true, antivirus: true }
    begin
      client.request(:get, "/storage/buckets/#{id}")
      client.request(:put, "/storage/buckets/#{id}", body: body.except(:bucketId))
    rescue AppwriteClient::Unavailable => error
      raise unless error.message.include?("404")
      client.request(:post, "/storage/buckets", body: body)
    end
    puts "Bucket privado configurado. Nenhuma permissão pública foi concedida."
  end
end
