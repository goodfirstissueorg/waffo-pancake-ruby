# frozen_string_literal: true

require_relative "requests"
require_relative "api/customer_actions"

module Waffo
  module Pancake
    # The API as one customer, authenticated with a session token from
    # Client#issue_session_token. Use Client#customer to build one.
    #
    # A token is a bearer credential and is not bound to an environment, so X-Environment is
    # required. `inspect` hides the token, so it cannot reach a log through an error report.
    class CustomerSession
      include Requests
      include API::CustomerActions

      attr_reader :environment

      def initialize(token:, environment:, connection:)
        raise ConfigurationError, "Missing session token" if token.to_s.strip.empty?

        @token = token
        @environment = Requests.environment!(environment)
        @connection = connection
      end

      # `language` is required: without it Waffo answers 400 "Invalid input" and does not name
      # the field. buyer_email: is required unless the checkout session already has one. Optional:
      # user_terminal ("web" or "app").
      def create_onetime_order(checkout_session_id:, billing_detail:, language:, **params)
        create_order("/v1/actions/onetime-order/create-order", checkout_session_id, billing_detail, language, params)
      end

      def create_subscription_order(checkout_session_id:, billing_detail:, language:, **params)
        create_order("/v1/actions/subscription-order/create-order", checkout_session_id, billing_detail, language, params)
      end

      def inspect = "#<#{self.class} environment=#{@environment.inspect}>"

      private
        attr_reader :connection

        def create_order(path, checkout_session_id, billing_detail, language, params)
          raise ArgumentError, "language is required" if blank?(language)

          action(path, checkout_session_id: checkout_session_id, billing_detail: billing_detail, language: language,
                       **params)
        end

        def auth_headers(_path, _json)
          { "Authorization" => "Bearer #{@token}", "X-Environment" => @environment }
        end
    end
  end
end
