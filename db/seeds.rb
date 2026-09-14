Plan.find_or_create_by!(name: "Studio") do |plan|
  plan.features = Plan::FEATURES.to_h { |key| [key, true] }
  plan.limits = Plan::LIMITS
  plan.offline_hours = 24
end
RegistrationSetting.find_or_create_by!(id: 1) do |settings|
  settings.plan = Plan.find_by!(name: "Studio")
  settings.installation_limit = Integer(ENV.fetch("INITIAL_INSTALLATION_LIMIT", "20"))
end
