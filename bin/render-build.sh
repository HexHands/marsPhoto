#!/usr/bin/env bash
set -o errexit

bundle install

# If this app uses assets (it appears to have a frontend under /public), keep these:
bundle exec rails assets:precompile
bundle exec rails assets:clean

# Run migrations during build (common for simple setups)
bundle exec rails db:migrate
