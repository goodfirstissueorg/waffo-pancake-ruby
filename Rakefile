# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

namespace :test do
  # Its own process, so nothing from Rails is loaded: the core must work without it.
  Rake::TestTask.new(:core) do |t|
    t.libs << "test" << "lib"
    t.test_files = FileList["test/*_test.rb"]
  end

  Rake::TestTask.new(:rails) do |t|
    t.libs << "test" << "lib"
    t.test_files = FileList["test/rails/**/*_test.rb"]
  end
end

desc "Run the core and the Rails integration tests"
task test: %w[test:core test:rails]

task default: :test
