# frozen_string_literal: true

require "base64"
require "json"
require "net/http"
require "openssl"
require "time"
require "uri"

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
    # hashes (metadata, prices, billing details) are sent exactly as given.
    class Client
      DEFAULT_BASE_URL = "https://api.waffo.ai"
      DEFAULT_TIMEOUT = 15

      NETWORK_ERRORS = [
        Timeout::Error, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError, Net::HTTPBadResponse
      ].freeze

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

      attr_reader :merchant_id, :base_url, :store_id

      # The canonical request the gateway checks `X-Signature` against: method, path,
      # timestamp (seconds) and the base64 SHA-256 of the body, one per line.
      def self.sign(method:, path:, timestamp:, body:, private_key:)
        body_hash = Base64.strict_encode64(OpenSSL::Digest::SHA256.digest(body))
        canonical = "#{method}\n#{path}\n#{timestamp}\n#{body_hash}"
        Base64.strict_encode64(private_key.sign(OpenSSL::Digest::SHA256.new, canonical))
      end

      # Every argument defaults to Waffo::Pancake.configuration (itself defaulting to the
      # WAFFO_* environment variables). `transport` replaces the HTTP call: it takes the URI,
      # the headers and the JSON body and answers `[status, body]` (status nil when there was
      # no answer). `logger` gets one info line per request and `instrumenter` one
      # `request.waffo_pancake` event; neither ever sees the body or the key.
      def initialize(config: Pancake.configuration, merchant_id: config.merchant_id, private_key: config.private_key,
                     store_id: config.store_id, base_url: config.base_url, timeout: config.timeout, logger: config.logger,
                     instrumenter: config.instrumenter, transport: nil)
        raise ConfigurationError, "Missing merchant_id (WAFFO_MERCHANT_ID)" if blank?(merchant_id)
        raise ConfigurationError, "Missing private_key (WAFFO_PRIVATE_KEY)" if blank?(private_key)

        @merchant_id = merchant_id
        @store_id = blank?(store_id) ? nil : store_id
        @private_key = Keys.private_key(private_key)
        @base_url = base_url.to_s.chomp("/")
        @timeout = timeout
        @logger = logger
        @instrumenter = instrumenter
        @transport = transport || method(:http_post)
      end

      # --- Checkout ----------------------------------------------------------------------

      # `purpose: "portal"` signs the customer into the store's customer portal instead; see
      # create_customer_portal_link.
      def issue_session_token(buyer_identity:, store_id: nil, product_id: nil, purpose: nil)
        raise ArgumentError, "store_id or product_id is required" if store_id.nil? && product_id.nil?

        action("/v1/actions/auth/issue-session-token",
               { buyer_identity: buyer_identity, store_id: store_id, product_id: product_id, purpose: purpose })
      end

      # Anonymous checkout: the buyer fills everything in on the page.
      # Returns {"sessionId", "checkoutUrl", "expiresAt"}.
      def create_checkout_session(product_id:, currency:, **params)
        action("/v1/actions/checkout/create-session", { product_id: product_id, currency: currency, **params })
      end

      # Authenticated checkout: `buyer_identity` (your stable id for the customer) goes into a
      # session token, which Waffo uses for trial eligibility and the customer portal. The
      # token is appended to the checkout URL as a fragment (`#token=...`).
      def create_authenticated_checkout(product_id:, currency:, buyer_identity:, **params)
        token = issue_session_token(buyer_identity: buyer_identity, product_id: product_id)
        session = create_checkout_session(product_id: product_id, currency: currency, **params)
        session.merge(
          "checkoutUrl" => "#{session.fetch("checkoutUrl")}#token=#{token.fetch("token")}",
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

      # pending → canceled at once; active, trialing and past_due → canceling, ending with the
      # paid period. The terminal `canceled` arrives later as a webhook.
      def cancel_subscription(order_id)
        action("/v1/actions/subscription-order/cancel-order", { order_id: order_id })
      end

      # Undoes a cancellation while the order is still `canceling`.
      def reactivate_subscription(order_id)
        action("/v1/actions/subscription-order/reactivate-order", { order_id: order_id })
      end

      def cancel_onetime_order(order_id)
        action("/v1/actions/onetime-order/cancel-order", { order_id: order_id })
      end

      # Nil when Waffo knows no such order. `productId` is the order's current product, so a plan
      # change to another product can be told apart.
      def subscription_order(order_id)
        order = graphql(SUBSCRIPTION_ORDER_QUERY, id: order_id)&.dig("subscriptionOrder")
        order && order.merge("productId" => order.dig("subscriptionProduct", "id"))
      end

      # --- Products ----------------------------------------------------------------------

      # prices: { "USD" => { amount: "9.99", taxCategory: "saas" } }
      def create_subscription_product(store_id:, name:, billing_period:, prices:, **params)
        action("/v1/actions/subscription-product/create-product",
               { store_id: store_id, name: name, billing_period: billing_period, prices: prices, **params })
      end

      def update_subscription_product(id:, **params)
        action("/v1/actions/subscription-product/update-product", { id: id, **params })
      end

      # Copies the test version to production (first publish only).
      def publish_subscription_product(id:)
        action("/v1/actions/subscription-product/publish-product", { id: id })
      end

      def create_onetime_product(store_id:, name:, prices:, **params)
        action("/v1/actions/onetime-product/create-product", { store_id: store_id, name: name, prices: prices, **params })
      end

      # --- Webhook endpoints -------------------------------------------------------------

      def add_webhook(store_id:, url:, events:, test_mode:, channel: "http", **params)
        action("/v1/actions/store/add-webhook",
               { store_id: store_id, channel: channel, url: url, events: events, test_mode: test_mode, **params })
      end

      def remove_webhook(id:)
        action("/v1/actions/store/remove-webhook", { id: id })
      end

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

      # --- Low level ---------------------------------------------------------------------

      # Returns `data`. Raises when the response carries `errors` and no data.
      def graphql(query, variables = {})
        status, envelope = request("/v1/graphql", { "query" => query, "variables" => variables })
        raise_for(status, envelope, "/v1/graphql") if present?(envelope["errors"]) && envelope["data"].nil?

        envelope["data"]
      end

      # Any action endpoint. Returns the envelope's `data`; raises Rejected or Unavailable on
      # `errors` or a non-2xx status.
      def action(path, params)
        status, envelope = request(path, camelize(params))
        raise_for(status, envelope, path) if present?(envelope["errors"]) || !(200..299).cover?(status)

        envelope["data"] || {}
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

        def request(path, params)
          json = JSON.generate(params)
          timestamp = Time.now.to_i.to_s
          headers = {
            "Content-Type" => "application/json",
            "X-Merchant-Id" => @merchant_id,
            "X-Timestamp" => timestamp,
            "X-Signature" => self.class.sign(method: "POST", path: path, timestamp: timestamp, body: json,
                                             private_key: @private_key)
          }

          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          status, body = instrument("request.waffo_pancake", method: "POST", path: path) do |payload|
            call_transport(URI("#{@base_url}#{path}"), headers, json).tap { |answer| payload[:status] = answer.first }
          end
          elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(2)
          @logger&.info("[Waffo] POST #{path} status=#{status.inspect} in #{elapsed}s")

          raise Unavailable.new("Waffo #{path} unreachable: #{body}", status: nil) if status.nil?

          envelope = parse(body)
          raise_for(status, {}, path, "non-JSON response") unless envelope.is_a?(Hash)

          [status, envelope]
        end

        def instrument(name, payload, &block)
          return yield(payload) unless @instrumenter

          @instrumenter.instrument(name, payload, &block)
        end

        def call_transport(uri, headers, json)
          @transport.call(uri, headers, json)
        rescue *NETWORK_ERRORS => e
          [nil, "#{e.class}: #{e.message}"]
        end

        def http_post(uri, headers, json)
          request = Net::HTTP::Post.new(uri, headers)
          request.body = json
          response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: @timeout,
                                     read_timeout: @timeout, write_timeout: @timeout) do |http|
            http.request(request)
          end
          [response.code.to_i, response.body]
        end

        def raise_for(status, envelope, path, fallback = "request failed")
          errors = Array(envelope["errors"])
          message = errors.map { |e| e.is_a?(Hash) ? e["message"] : e.to_s }.compact.first || fallback
          error = status.nil? || status == 429 || status >= 500 ? Unavailable : Rejected
          raise error.new("Waffo #{path} status=#{status}: #{message}", status: status, errors: errors)
        end

        def parse(body)
          JSON.parse(body.to_s)
        rescue JSON::ParserError
          nil
        end

        def camelize(params)
          params.each_with_object({}) do |(key, value), out|
            next if value.nil?

            out[key.to_s.gsub(/_([a-z\d])/) { Regexp.last_match(1).upcase }] = value
          end
        end

        def blank?(value) = value.nil? || value.to_s.strip.empty?

        def present?(value) = !(value.nil? || (value.respond_to?(:empty?) && value.empty?))
    end
  end
end
