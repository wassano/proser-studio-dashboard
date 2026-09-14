class Registration
  def self.call(auth, metadata, ip)
    # One persistent row serializes admissions: concurrent requests cannot exceed the global cap.
    RegistrationSetting.current.with_lock do |settings|
      installation = Installation.find_by(device_id: auth.device_id)
      return installation if installation # Reinstallation never resets a revoked registration.
      installation = Installation.create!(metadata.merge(device_id: auth.device_id, public_key: auth.key_pem, last_ip: ip, location: GeoLocation.lookup(ip), last_seen_at: Time.current))
      settings = RegistrationSetting.current
      if settings.registration_enabled && Installation.where(status: "active").count < settings.installation_limit
        license = License.create!(plan: settings.plan, name: metadata.fetch(:computer_name), max_devices: 1)
        installation.approve!(license)
      end
      AuditEvent.create!(actor: "device:#{auth.device_id}", action: "installation.register", subject: installation.id.to_s, ip: ip, details: { status: installation.status })
      installation
    end
  end
end
