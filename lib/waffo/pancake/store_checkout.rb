# frozen_string_literal: true

require_relative "requests"
require_relative "connection"

module Waffo
  module Pancake
    # Anonymous storefront access, authenticated with only the store's public slug. It holds no
    # secret, so it suits code that cannot keep an API key.
    #
    #   storefront = Waffo::Pancake::StoreCheckout.new(store_slug: "my-store", environment: "test")
    #   storefront.create_checkout_session(product_id: "PROD_...", currency: "USD")
    class StoreCheckout
      include Requests

      attr_reader :store_slug, :environment

      def initialize(store_slug:, config: Pancake.configuration, environment: config.environment,
                     base_url: config.base_url, timeout: config.timeout, logger: config.logger,
                     instrumenter: config.instrumenter, transport: nil)
        raise ConfigurationError, "Missing store_slug" if store_slug.to_s.strip.empty?

        @store_slug = store_slug
        @environment = Requests.environment!(environment)
        @connection = Connection.new(base_url: base_url, timeout: timeout, logger: logger, instrumenter: instrumenter,
                                     transport: transport)
      end

      def create_checkout_session(product_id:, currency:, **params)
        action("/v1/actions/checkout/create-session", product_id: product_id, currency: currency, **params)
      end

      private
        attr_reader :connection

        def auth_headers(_path, _json)
          { "X-Store-Slug" => @store_slug, "X-Environment" => @environment }
        end
    end
  end
end
