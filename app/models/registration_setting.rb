class RegistrationSetting < ApplicationRecord
  belongs_to :plan
  validates :installation_limit, numericality: { only_integer: true, in: 0..100000 }
  validates :registration_enabled, inclusion: { in: [true, false] }
  def self.current = find(1)
end
