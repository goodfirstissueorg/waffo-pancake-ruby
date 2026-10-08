# frozen_string_literal: true

require_relative "rails_helper"
require "rails/generators/test_case"
require "generators/waffo_pancake/install/install_generator"

class InstallGeneratorTest < Rails::Generators::TestCase
  tests WaffoPancake::Generators::InstallGenerator
  destination File.expand_path("../../tmp/generator", __dir__)

  setup do
    prepare_destination
    FileUtils.mkdir_p(File.join(destination_root, "config"))
    File.write(File.join(destination_root, "config/routes.rb"), "Rails.application.routes.draw do\nend\n")
  end

  def test_installs_the_initializer_endpoint_and_events_table
    run_generator

    assert_file "config/initializers/waffo_pancake.rb", /Waffo::Pancake\.configure do \|config\|/
    assert_file "config/routes.rb", %r{post "webhooks/waffo", to: "waffo_webhooks#create", as: :waffo_webhook}
    assert_file "app/controllers/waffo_webhooks_controller.rb" do |controller|
      assert_match(/include Waffo::Pancake::WebhookController/, controller)
      assert_match(/WaffoWebhookEvent\.record\(waffo_event\)/, controller)
    end
    assert_migration "db/migrate/create_waffo_webhook_events.rb" do |migration|
      assert_match(/ActiveRecord::Migration\[\d+\.\d+\]/, migration)
      assert_match(/add_index :waffo_webhook_events, :delivery_id, unique: true/, migration)
    end
    assert_file "app/models/waffo_webhook_event.rb", /def self\.record\(event\)/
    assert_file "app/jobs/waffo_webhook_job.rb", /retry_on Waffo::Pancake::Unavailable/
  end

  def test_without_the_events_table
    run_generator ["--skip-events-table"]

    assert_file "app/controllers/waffo_webhooks_controller.rb" do |controller|
      refute_match(/WaffoWebhookEvent/, controller)
    end
    assert_no_migration "db/migrate/create_waffo_webhook_events.rb"
    assert_no_file "app/models/waffo_webhook_event.rb"
    assert_no_file "app/jobs/waffo_webhook_job.rb"
  end

  def test_generated_ruby_parses
    run_generator

    %w[config/initializers/waffo_pancake.rb app/controllers/waffo_webhooks_controller.rb app/models/waffo_webhook_event.rb
       app/jobs/waffo_webhook_job.rb].each do |path|
      assert RubyVM::InstructionSequence.compile_file(File.join(destination_root, path)), path
    end
  end
end
