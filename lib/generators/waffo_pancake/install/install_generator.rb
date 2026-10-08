# frozen_string_literal: true

require "rails/generators"
require "rails/generators/migration"

module WaffoPancake
  module Generators
    # bin/rails generate waffo_pancake:install [--skip-events-table]
    class InstallGenerator < ::Rails::Generators::Base
      include ::Rails::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      desc "Adds a Waffo Pancake initializer and a verified webhook endpoint, with a table that " \
           "records each delivery once and a job that handles it."

      class_option :events_table, type: :boolean, default: true,
                                  desc: "Record deliveries in waffo_webhook_events and handle them in a job"

      def self.next_migration_number(dirname)
        require "rails/generators/active_record"
        ::ActiveRecord::Generators::Base.next_migration_number(dirname)
      end

      def create_initializer
        template "initializer.rb", "config/initializers/waffo_pancake.rb"
      end

      def create_controller
        template "webhooks_controller.rb", "app/controllers/waffo_webhooks_controller.rb"
      end

      def add_route
        route 'post "webhooks/waffo", to: "waffo_webhooks#create", as: :waffo_webhook'
      end

      def create_events_table
        return unless events_table?

        migration_template "create_waffo_webhook_events.rb", "db/migrate/create_waffo_webhook_events.rb"
        template "webhook_event.rb", "app/models/waffo_webhook_event.rb"
        template "webhook_job.rb", "app/jobs/waffo_webhook_job.rb"
      end

      def show_next_steps
        say <<~TEXT

          Waffo Pancake is installed. Next:
            1. Add credentials (bin/rails credentials:edit) or WAFFO_* environment variables:
                 waffo:
                   merchant_id: MER_...
                   private_key: "-----BEGIN PRIVATE KEY-----\\n..."
                   store_id: STO_...
                   environment: test
            #{events_table? ? "2. bin/rails db:migrate" : "2. Deduplicate deliveries on waffo_event[\"id\"] in WaffoWebhooksController"}
            3. In the Waffo Dashboard, add a webhook pointing at https://<your host>/webhooks/waffo
               and subscribe to the events you handle.
        TEXT
      end

      private
        def events_table? = options[:events_table]

        def migration_version
          "[#{::ActiveRecord::Migration.current_version}]" if defined?(::ActiveRecord::Migration)
        end
    end
  end
end
