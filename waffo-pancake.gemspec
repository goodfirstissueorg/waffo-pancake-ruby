# frozen_string_literal: true

require_relative "lib/waffo/pancake/version"

Gem::Specification.new do |spec|
  spec.name = "waffo-pancake"
  spec.version = Waffo::Pancake::VERSION
  spec.authors = ["Good First Issue"]
  spec.email = ["hi@goodfirstissue.org"]

  spec.summary = "Ruby client for the Waffo Pancake merchant API"
  spec.description = "Signed requests to the Waffo Pancake merchant API (checkout, subscriptions, products, " \
                     "GraphQL) and webhook signature verification. A Ruby port of @waffo/pancake-ts."
  spec.homepage = "https://github.com/goodfirstissueorg/waffo-pancake-ruby"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => "#{spec.homepage}/tree/main",
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*", "README.md", "CHANGELOG.md", "LICENSE"].select { |path| File.file?(path) }
  spec.require_paths = ["lib"]

  # base64 left the default gems in Ruby 3.4.
  spec.add_dependency "base64", ">= 0.1"
end
