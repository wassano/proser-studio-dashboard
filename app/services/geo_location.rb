class GeoLocation
  def self.lookup(ip)
    path = ENV["GEOIP_DB_PATH"]
    return nil if path.blank? || !File.file?(path)
    reader = MaxMind::DB.new(path, mode: MaxMind::DB::MODE_FILE)
    record = reader.get(ip)
    return nil unless record
    [record.dig("city", "names", "pt-BR") || record.dig("city", "names", "en"), record.dig("subdivisions", 0, "iso_code"), record.dig("country", "iso_code")].compact.join(", ").presence
  ensure
    reader&.close
  end
end
