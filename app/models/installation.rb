class Installation < ApplicationRecord
  belongs_to :license, optional: true
  has_many :download_grants, dependent: :delete_all
  validates :device_id, uniqueness: true, format: { with: /\A[a-f0-9]{64}\z/ }
  validates :status, inclusion: { in: %w[pending active rejected revoked] }
  validates :computer_name, :os, :arch, :app_version, :target, presence: true, length: { maximum: 160 }
  validates :target, inclusion: { in: %w[win-x64 win7-x64 mac-arm64 mac-x64] }
  validates :app_version, format: { with: /\A\d+\.\d+\.\d+\z/ }
  def access_status
    return status unless status == "active"
    return "blocked" unless license&.usable?
    return "upgrade_required" if Gem::Version.new(app_version) < Gem::Version.new(license.minimum_version)
    "active"
  end
  def approve!(assigned_license)
    assigned_license.with_lock do
      with_lock do
        raise Policy::Denied, "Licença indisponível" unless assigned_license.usable?
        count = assigned_license.installations.where(status: "active").where.not(id: id).count
        raise Policy::Denied, "Limite de computadores atingido" if count >= assigned_license.max_devices
        update!(license: assigned_license, status: "active", activated_at: activated_at || Time.current)
      end
    end
  end
end
