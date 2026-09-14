class AdminSession < ApplicationRecord
  has_many :release_uploads, dependent: :destroy
end
