class Policy
  class Denied < StandardError; end
  def self.validate(record, features, limits, partial:)
    unless features.is_a?(Hash) && (features.keys - Plan::FEATURES).empty? && features.values.all? { |v| v == true || v == false } && (partial || features.keys.sort == Plan::FEATURES.sort)
      record.errors.add(:features, "recursos inválidos ou incompletos")
    end
    unless limits.is_a?(Hash) && (limits.keys - Plan::LIMITS.keys).empty? && limits.all? { |k, v| v.is_a?(Integer) && v.between?(0, Plan::LIMITS.fetch(k, -1)) } && (partial || limits.keys.sort == Plan::LIMITS.keys.sort)
      record.errors.add(:limits, "limites inválidos ou incompletos")
    end
  end
end
