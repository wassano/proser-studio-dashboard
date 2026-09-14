FROM node:24-bookworm-slim AS frontend
WORKDIR /frontend
COPY frontend/package*.json ./
RUN npm ci
COPY frontend/ ./
RUN npm run build

FROM ruby:3.3-slim AS gems
WORKDIR /rails
RUN apt-get update && apt-get install -y --no-install-recommends build-essential libpq-dev libyaml-dev && rm -rf /var/lib/apt/lists/*
COPY Gemfile Gemfile.lock ./
RUN bundle config set without 'development test' && bundle install --jobs 2 && rm -rf /usr/local/bundle/cache

FROM ruby:3.3-slim
WORKDIR /rails
RUN apt-get update && apt-get install -y --no-install-recommends libpq5 libyaml-0-2 curl ca-certificates && rm -rf /var/lib/apt/lists/* && groupadd --gid 10001 proser && useradd --uid 10001 --gid 10001 --create-home proser
ENV RAILS_ENV=production BUNDLE_WITHOUT=development:test BUNDLE_USER_HOME=/rails/tmp/bundle TMPDIR=/rails/tmp/uploads
COPY --from=gems /usr/local/bundle /usr/local/bundle
COPY --chown=proser:proser . .
COPY --from=frontend --chown=proser:proser /public ./public
RUN mkdir -p tmp/pids tmp/uploads tmp/bundle log storage && chown -R proser:proser tmp log storage
USER 10001:10001
EXPOSE 3000
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
