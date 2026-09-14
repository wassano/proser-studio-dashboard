class AuditEvent < ApplicationRecord
  def readonly? = persisted?
end
