# frozen_string_literal: true

module Waffo
  module Pancake
    # Process-wide settings, read by `Waffo::Pancake.client`, `Waffo::Pancake.verify_webhook`
    # and the Rails integration. Every value starts from its environment variable; the Railtie
    # then applies `credentials.waffo`, and `Waffo::Pancake.configure` has the last word.
    class Configuration
      ENVIRONMENTS = %w[test prod].freeze

      # MER_..., the API key's private key (PEM, PEM with literal \n, or bare base64), STO_...
      attr_accessor :merchant_id, :private_key, :store_id
      attr_accessor :base_url, :timeout, :logger
      # A key used instead of the built-in platform keys; nil uses those.
      attr_accessor :webhook_public_key
      # Seconds a webhook timestamp may lie in the past (0 skips the check) or in the future.
      attr_accessor :webhook_tolerance, :webhook_future_tolerance
      # Anything answering `instrument(name, payload) { |payload| ... }`. Defaults to
      # ActiveSupport::Notifications when it is loaded; nil turns instrumentation off.
      attr_writer :instrumenter

      # "test" or "prod": which platform key verifies webhooks, and which deliveries the Rails
      # webhook concern accepts. nil tries prod, then test, and accepts both.
      attr_reader :environment

      def initialize
        @merchant_id = ENV["WAFFO_MERCHANT_ID"]
        @private_key = ENV["WAFFO_PRIVATE_KEY"]
        @store_id = ENV["WAFFO_STORE_ID"]
        begin
          self.environment = ENV["WAFFO_ENVIRONMENT"]
        rescue ConfigurationError => e
          raise ConfigurationError, "WAFFO_ENVIRONMENT: #{e.message}"
        end
        @base_url = ENV["WAFFO_API_BASE_URL"] || Client::DEFAULT_BASE_URL
        @timeout = Client::DEFAULT_TIMEOUT
        @logger = nil
        @webhook_public_key = nil
        @webhook_tolerance = Webhook::DEFAULT_TOLERANCE
        @webhook_future_tolerance = Webhook::DEFAULT_FUTURE_TOLERANCE
        @instrumenter = :default
      end

      def environment=(value)
        value = value.to_s.strip.downcase
        value = nil if value.empty?
        unless value.nil? || ENVIRONMENTS.include?(value)
          raise ConfigurationError, "environment must be test or prod, got #{value.inspect}"
        end

        @environment = value
      end

      def instrumenter
        return @instrumenter unless @instrumenter == :default

        defined?(::ActiveSupport::Notifications) ? ::ActiveSupport::Notifications : nil
      end

      # What a client needs; a store id is only checked by the webhook concern.
      def configured?
        !blank?(merchant_id) && !blank?(private_key)
      end

      private
        def blank?(value) = value.nil? || value.to_s.strip.empty?
    end

    @mutex = Mutex.new

    class << self
      def configuration
        @configuration || @mutex.synchronize { @configuration ||= Configuration.new }
      end

      # Yields the configuration; the shared client is rebuilt on its next use.
      def configure
        yield configuration
        reset_client!
        configuration
      end

      # A client built from the configuration, shared by the process. Raises
      # ConfigurationError while the merchant id or the key is missing.
      def client
        return @client if @client

        config = configuration
        @mutex.synchronize { @client ||= Client.new(config: config) }
      end

      # Replaces the shared client, for example with Waffo::Pancake::TestHelpers::FakeClient.
      attr_writer :client

      def reset_client!
        @mutex.synchronize { @client = nil }
      end

      # Back to the environment variables, with no shared client.
      def reset!
        @mutex.synchronize do
          @configuration = nil
          @client = nil
        end
      end

      # Webhook.verify with the configured environment, key and tolerances, reported as a
      # `verify_webhook.waffo_pancake` event (with `:exception` when it is refused).
      def verify_webhook(payload, signature_header, now: Time.now)
        config = configuration
        verify = lambda do |event_payload|
          event = Webhook.verify(payload, signature_header, environment: config.environment,
                                                            public_key: config.webhook_public_key,
                                                            tolerance: config.webhook_tolerance,
                                                            future_tolerance: config.webhook_future_tolerance, now: now)
          event_payload.merge!(event_id: event["id"], event_type: event["eventType"], mode: event["mode"]) if event.is_a?(Hash)
          event
        end

        instrumenter = config.instrumenter
        details = { environment: config.environment }
        instrumenter ? instrumenter.instrument("verify_webhook.waffo_pancake", details, &verify) : verify.call(details)
      end
    end
  end
end
