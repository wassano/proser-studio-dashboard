namespace :proser do
  desc "Remove nonces, downloads e sessões expirados; execute periodicamente"
  task prune: :environment do
    RequestNonce.where("expires_at < ?", Time.current).delete_all
    DownloadGrant.where("expires_at < ?", Time.current).delete_all
    inactive_sessions = AdminSession.where("expires_at < ? OR last_seen_at < ?", Time.current, 1.hour.ago).select(:id)
    ReleaseUpload.where("expires_at < ?", Time.current).or(ReleaseUpload.where(admin_session_id: inactive_sessions)).find_each do |upload|
      upload.with_lock { upload.destroy! }
    end
    AdminSession.where("expires_at < ? OR last_seen_at < ?", Time.current, 1.hour.ago).delete_all
    days = Integer(ENV.fetch("AUDIT_RETENTION_DAYS", "180"))
    AuditEvent.where("created_at < ?", days.days.ago).delete_all
  end
end
