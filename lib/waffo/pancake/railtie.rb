# frozen_string_literal: true

require "rails/railtie"

module Waffo
  module Pancake
    # Loaded only inside a Rails app. Settings are applied in this order, the last one winning:
    #
    #   1. WAFFO_* environment variables
    #   2. credentials.waffo (merchant_id, private_key, store_id, environment, webhook_public_key)
    #   3. config.waffo_pancake.* in config/application.rb or an environment file
    #   4. Waffo::Pancake.configure in config/initializers
    #
    # The logger defaults to Rails.logger, `private_key` is filtered from logs, and so is a
    # redirect to a URL carrying a session token (`#token=`, authenticated checkout and the
    # customer portal). Deprecated webhook fields are reported through `Railtie.deprecator`,
    # registered as `Rails.application.deprecators[:waffo_pancake]`.
    class Railtie < ::Rails::Railtie
      CREDENTIAL_KEYS = %i[merchant_id private_key store_id environment webhook_public_key].freeze

      TOKEN_FRAGMENT = "#token="

      config.waffo_pancake = ActiveSupport::OrderedOptions.new

      def self.deprecator
        @deprecator ||= ActiveSupport::Deprecation.new("1.0", "waffo-pancake")
      end

      initializer "waffo_pancake.filter_parameters" do |app|
        app.config.filter_parameters |= [:private_key]
        app.config.filter_redirect |= [TOKEN_FRAGMENT] if app.config.respond_to?(:filter_redirect)
      end

      initializer "waffo_pancake.deprecator" do |app|
        app.deprecators[:waffo_pancake] = Railtie.deprecator if app.respond_to?(:deprecators)
      end

      initializer "waffo_pancake.configuration" do |app|
        Waffo::Pancake.configure do |config|
          credentials = app.credentials[:waffo] if app.respond_to?(:credentials)
          CREDENTIAL_KEYS.each do |key|
            value = credentials&.[](key)
            config.public_send(:"#{key}=", value) unless value.nil? || value.to_s.strip.empty?
          end

          app.config.waffo_pancake.each { |key, value| config.public_send(:"#{key}=", value) }
          config.logger ||= ::Rails.logger
          config.deprecator = Railtie.deprecator unless app.config.waffo_pancake.key?(:deprecator)
        end
      end
    end
  end
end
