source "https://rubygems.org"
ruby ">= 3.2.0"
gem "rails", "~> 8.1.0"
gem "json", "~> 2.0" # Rails 8.1 still passes a positional options hash to JSON.parse.
gem "puma", "~> 7.0"
gem "pg", "~> 1.6"
gem "sqlite3", "~> 2.0", groups: %i[development test]
gem "redis", "~> 5.0"
gem "rack-attack", "~> 6.8"
gem "maxmind-db", "~> 1.3"
gem "dotenv-rails", "~> 3.1", groups: %i[development test]
group :test do
  gem "minitest", "~> 5.25"
  gem "webmock", "~> 3.25"
end
