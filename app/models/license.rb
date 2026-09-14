class License < ApplicationRecord
  belongs_to :plan
  has_many :installations, dependent: :restrict_with_exception
  validates :name, presence: true, length: { maximum: 120 }
  validates :status, inclusion: { in: %w[active suspended revoked] }
  validates :channel, inclusion: { in: %w[stable beta] }
  validates :max_devices, numericality: { only_integer: true, in: 1..1000 }
  validates :minimum_version, format: { with: /\A\d+\.\d+\.\d+\z/ }
  validate { Policy.validate(self, feature_overrides, limit_overrides, partial: true) }
  validate do
    if persisted? && installations.where(status: "active").count > max_devices.to_i
      errors.add(:max_devices, "desative instalações antes de reduzir o limite")
    end
  end
  def usable? = status == "active" && (expires_at.nil? || expires_at > Time.current)
  def effective_features = plan.features.merge(feature_overrides)
  def effective_limits = plan.limits.merge(limit_overrides)
end
