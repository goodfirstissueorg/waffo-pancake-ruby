# frozen_string_literal: true

source "https://rubygems.org"

gemspec

gem "minitest", "~> 5.25"
gem "rake", "~> 13.0"

# The Rails integration's tests (test/rails); the gem itself does not depend on Rails.
group :rails do
  gem "actionpack", ">= 7.1"
  gem "activerecord", ">= 7.1"
  gem "railties", ">= 7.1"
end
