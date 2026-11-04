# frozen_string_literal: true

require "base64"
require "json"
require "openssl"
require "time"

require_relative "connection"
require_relative "requests"
require_relative "api/customer_actions"
require_relative "api/store_actions"
require_relative "api/product_actions"
require_relative "api/promotion_actions"
require_relative "api/queries"
require_relative "customer_session"

module Waffo
  module Pancake
    # The merchant API, authenticated with an API key: every request is a POST signed with the
    # key's RSA private key. An API key is bound to test or prod when it is created, so no
    # environment header is sent.
    #
    #   client = Waffo::Pancake::Client.new(merchant_id: "MER_...", private_key: ENV["WAFFO_PRIVATE_KEY"])
    #   client.cancel_subscription("ORD_...") # => {"orderId" => "ORD_...", "status" => "canceling"}
    #
    # Parameters may be given in snake_case; top-level keys are sent in camelCase. Nested
    # hashes (metadata, prices, billing details) are sent exactly as given. Every action takes
    # `idempotency_key:`. Routes that do not take an API key are reached through #customer.
    class Client
      include Requests
      include API::CustomerActions
      include API::StoreActions
      include API::ProductActions
      include API::PromotionActions
      include API::Queries

      DEFAULT_BASE_URL = "https://api.waffo.ai"
      DEFAULT_TIMEOUT = 15
      NETWORK_ERRORS = Connection::NETWORK_ERRORS

      SUBSCRIPTION_ORDER_QUERY = <<~GRAPHQL
        query ($id: String!) {
          subscriptionOrder(id: $id) {
            id storeId status testMode buyerEmail merchantProvidedBuyerIdentity orderMerchantExternalId
            billingPeriod currentPeriodStart currentPeriodEnd canceledAt
            subscriptionProduct { id }
          }
        }
      GRAPHQL

      WEBHOOK_DELIVERY_FIELDS = "id storeId eventType eventId payload webhookUrl status httpStatus responseBody " \
                                "attemptCount lastAttemptedAt createdAt"
      WEBHOOK_DELIVERY_STATUSES = %w[pending success failed].freeze

      attr_reader :merchant_id, :base_url, :store_id, :environment

      # The canonical request the gateway checks `X-Signature` against: method, path,
      # timestamp (seconds) and the base64 SHA-256 of the body, one per line.
      def self.sign(method:, path:, timestamp:, body:, private_key:)
        body_hash = Base64.strict_encode64(OpenSSL::Digest::SHA256.digest(body))
        canonical = "#{method}\n#{path}\n#{timestamp}\n#{body_hash}"
        Base64.strict_encode64(private_key.sign(OpenSSL::Digest::SHA256.new, canonical))
      end

      # Every argument defaults to Waffo::Pancake.configuration (itself defaulting to the
      # WAFFO_* environment variables). `transport` replaces the HTTP call: it takes the URI,
      # the headers and the JSON body and answers `[status, body]` or `[status, body, headers]`
      # (status nil when there was no answer). `logger` gets one info line per request and
      # `instrumenter` one `request.waffo_pancake` event; neither ever sees the body or the key.
      #
      # The key's environment cannot be read from the key, so `environment` only tells #customer
      # and create_authenticated_plan_change which one to use.
      def initialize(config: Pancake.configuration, merchant_id: config.merchant_id, private_key: config.private_key,
                     store_id: config.store_id, environment: config.environment, base_url: config.base_url,
                     timeout: config.timeout, logger: config.logger, instrumenter: config.instrumenter, transport: nil)
        raise ConfigurationError, "Missing merchant_id (WAFFO_MERCHANT_ID)" if blank?(merchant_id)
        raise ConfigurationError, "Missing private_key (WAFFO_PRIVATE_KEY)" if blank?(private_key)

        @merchant_id = merchant_id
        @store_id = blank?(store_id) ? nil : store_id
        @environment = blank?(environment) ? nil : Requests.environment!(environment)
        @private_key = Keys.private_key(private_key)
        @base_url = base_url.to_s.chomp("/")
        @connection = Connection.new(base_url: @base_url, timeout: timeout, logger: logger, instrumenter: instrumenter,
                                     transport: transport)
      end

      def inspect = "#<#{self.class} merchant_id=#{@merchant_id.inspect} environment=#{@environment.inspect}>"

      # The same connection, authenticated as a customer with a token from issue_session_token.
      def customer(token, environment: @environment)
        CustomerSession.new(token: token, environment: environment, connection: @connection)
      end

      # --- Checkout ----------------------------------------------------------------------

      # `purpose: "portal"` signs the customer into the store's customer portal instead; see
      # create_customer_portal_link.
      def issue_session_token(buyer_identity:, store_id: nil, product_id: nil, purpose: nil, idempotency_key: nil)
        raise ArgumentError, "store_id or product_id is required" if store_id.nil? && product_id.nil?

        action("/v1/actions/auth/issue-session-token", buyer_identity: buyer_identity, store_id: store_id,
                                                       product_id: product_id, purpose: purpose,
                                                       idempotency_key: idempotency_key)
      end

      # Authenticated checkout: `buyer_identity` (your stable id for the customer) goes into a
      # session token, which Waffo uses for trial eligibility and the customer portal. The
      # token is appended to the checkout URL as a fragment (`#token=...`). `idempotency_key`
      # applies to the session only: a token is short-lived and cheap to issue again.
      def create_authenticated_checkout(product_id:, currency:, buyer_identity:, **params)
        token = issue_session_token(buyer_identity: buyer_identity, product_id: product_id)
        session = create_checkout_session(product_id: product_id, currency: currency, **params)
        session.merge(
          "checkoutUrl" => "#{session.fetch("checkoutUrl")}#token=#{token.fetch("token")}",
          "token" => token["token"],
          "tokenExpiresAt" => token["expiresAt"]
        )
      end

      # A plan change the customer confirms on Waffo's page. The URL is a bearer credential, like
      # the one from create_customer_portal_link. Needs a known environment, because a test
      # session needs `?test=true` before the fragment, and prod must not have it.
      def create_authenticated_plan_change(origin_order_id:, product_id:, currency:, buyer_identity:, **params)
        environment = Requests.environment!(@environment)
        token = issue_session_token(buyer_identity: buyer_identity, product_id: product_id)
        session = create_plan_change_session(origin_order_id: origin_order_id, product_id: product_id,
                                             currency: currency, **params)
        url = session.fetch("checkoutUrl")
        url = "#{url}#{url.include?("?") ? "&" : "?"}test=true" if environment == "test"
        session.merge(
          "checkoutUrl" => "#{url}#token=#{token.fetch("token")}",
          "token" => token["token"],
          "tokenExpiresAt" => token["expiresAt"]
        )
      end

      # --- Customer portal ----------------------------------------------------------------

      # Signs a customer who is signed in on your site into the store's customer portal, with no
      # email code. Returns {"portalUrl" => "https://...#token=...", "expiresAt" => ISO 8601}.
      #
      # `buyer_identity` is the one given at authenticated checkout, taken from your own session,
      # never from the request; `store_id` defaults to the configured store. The portal opens on
      # the API key's environment. The URL is a bearer credential: make one per click, answer
      # it with a 302 (Cache-Control: no-store, Referrer-Policy: no-referrer), and never log,
      # cache or send it. Waffo::Pancake::CustomerPortalController does that in Rails.
      def create_customer_portal_link(buyer_identity:, store_id: @store_id)
        raise ArgumentError, "store_id is required (WAFFO_STORE_ID)" if blank?(store_id)
        raise ArgumentError, "buyer_identity is required" if blank?(buyer_identity)

        path = "/v1/actions/auth/issue-session-token"
        data = issue_session_token(buyer_identity: buyer_identity.to_s, store_id: store_id, purpose: "portal")
        %w[portalUrl token].each do |key|
          next unless blank?(data[key])

          raise Rejected.new("Waffo #{path}: response has no #{key} for purpose portal", status: 200)
        end

        { "portalUrl" => "#{data["portalUrl"]}#token=#{data["token"]}", "expiresAt" => data["expiresAt"] }
      end

      # --- Orders ------------------------------------------------------------------------

      # Nil when Waffo knows no such order. `productId` is the order's current product, so a plan
      # change to another product can be told apart.
      def subscription_order(order_id)
        order = graphql(SUBSCRIPTION_ORDER_QUERY, id: order_id)&.dig("subscriptionOrder")
        order && order.merge("productId" => order.dig("subscriptionProduct", "id"))
      end

      # --- Webhook deliveries ------------------------------------------------------------

      # Delivery records, newest first, for the API key's environment: id, eventType, eventId,
      # payload, webhookUrl, status (pending / success / failed), httpStatus, responseBody,
      # attemptCount, lastAttemptedAt and createdAt.
      #
      # Waffo has no redelivery: a delivery that failed every retry stays failed. To process it
      # again, hand Waffo::Pancake::Webhook::Event.wrap(delivery["payload"]) to your handler.
      #
      # `filter` takes Waffo's GraphQL filter fields, e.g. { eventType: { eq: "refund.succeeded" } };
      # `status` and `event_type` are shortcuts for an `eq` on those fields.
      def webhook_deliveries(store_id: @store_id, status: nil, event_type: nil, filter: nil, limit: 20, offset: 0)
        filter = delivery_filter(status, event_type, filter)
        query = "query ($storeId: String!, $limit: Int, $offset: Int) { webhookDeliveries(storeId: $storeId, " \
                "limit: $limit, offset: $offset#{filter}) { #{WEBHOOK_DELIVERY_FIELDS} } }"
        graphql(query, storeId: require_store_id(store_id), limit: Integer(limit), offset: Integer(offset))
          &.fetch("webhookDeliveries", nil) || []
      end

      def webhook_deliveries_count(store_id: @store_id, status: nil, event_type: nil, filter: nil)
        filter = delivery_filter(status, event_type, filter)
        query = "query ($storeId: String!) { webhookDeliveriesCount(storeId: $storeId#{filter}) }"
        graphql(query, storeId: require_store_id(store_id))&.fetch("webhookDeliveriesCount", nil)
      end

      # A Ruby value as a GraphQL input literal: hashes as input objects, symbols and times as strings.
      def self.graphql_literal(value)
        case value
        when Hash
          fields = value.map do |key, field|
            raise ArgumentError, "invalid GraphQL field name #{key.inspect}" unless key.to_s.match?(/\A[_A-Za-z]\w*\z/)

            "#{key}: #{graphql_literal(field)}"
          end
          "{ #{fields.join(", ")} }"
        when Array then "[#{value.map { |item| graphql_literal(item) }.join(", ")}]"
        when Symbol then graphql_literal(value.to_s)
        when Time then JSON.generate(value.utc.iso8601(3))
        when String, Integer, Float, true, false, nil then JSON.generate(value)
        else raise ArgumentError, "cannot send #{value.class} in a GraphQL filter"
        end
      end

      private
        attr_reader :connection

        def auth_headers(path, json)
          timestamp = Time.now.to_i.to_s
          {
            "X-Merchant-Id" => @merchant_id,
            "X-Timestamp" => timestamp,
            "X-Signature" => self.class.sign(method: "POST", path: path, timestamp: timestamp, body: json,
                                             private_key: @private_key)
          }
        end

        def delivery_filter(status, event_type, filter)
          if status && !WEBHOOK_DELIVERY_STATUSES.include?(status.to_s)
            raise ArgumentError, "status must be one of #{WEBHOOK_DELIVERY_STATUSES.join(", ")}"
          end

          filter = (filter || {}).to_h.transform_keys(&:to_s)
          filter["status"] = { "eq" => status.to_s } if status
          filter["eventType"] = { "eq" => event_type.to_s } if event_type
          filter.empty? ? "" : ", filter: #{self.class.graphql_literal(filter)}"
        end

        def require_store_id(store_id)
          raise ArgumentError, "store_id is required (WAFFO_STORE_ID)" if blank?(store_id)

          store_id
        end
    end
  end
end
