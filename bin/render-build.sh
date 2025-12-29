#!/usr/bin/env bash
set -o errexit

bundle install

# Free Render: do migrations during build (since preDeployCommand needs paid) 
bundle exec rails db:migrate
