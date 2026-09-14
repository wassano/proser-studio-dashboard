class Plan < ApplicationRecord
  FEATURES = %w[lighting audio video scenes rdm effects video_capture powerpoint].freeze
  LIMITS = { "fixtures" => 170, "audios" => 256, "videos" => 512, "scenes" => 128 }.freeze
  has_many :licenses, dependent: :restrict_with_exception
  validates :name, presence: true, length: { maximum: 100 }
  validates :offline_hours, numericality: { only_integer: true, in: 1..168 }
  validate { Policy.validate(self, features, limits, partial: false) }
end
