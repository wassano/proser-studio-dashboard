class ReleaseAsset < ApplicationRecord
  belongs_to :release
  validates :filename, format: { with: /\A[a-zA-Z0-9][a-zA-Z0-9._ -]{0,179}\.(exe|zip|dmg|blockmap)\z/ }, uniqueness: { scope: :release_id }
  validates :size, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 2.gigabytes }
end
