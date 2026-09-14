class DownloadGrant < ApplicationRecord
  belongs_to :installation
  belongs_to :release
end
