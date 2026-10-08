# frozen_string_literal: true

require "securerandom"
require "time"
require "waffo/pancake"

module Waffo
  module Pancake
    # Helpers for an app's own tests (Minitest or RSpec):
    #
    #   # test/test_helper.rb                       # spec/rails_helper.rb
    #   require "waffo/pancake/test_helpers"        require "waffo/pancake/test_helpers"
    #   class ActiveSupport::TestCase               RSpec.configure do |config|
    #     include Waffo::Pancake::TestHelpers         config.include Waffo::Pancake::TestHelpers
    #   end                                         end
    #
    # `with_waffo_webhook_key` makes the configuration trust a throwaway key, and
    # `waffo_webhook_headers` signs a body with it, so a request test can post a delivery the
    # real verification accepts. `with_fake_waffo_client` swaps the shared client for a
    # FakeClient, which records calls instead of making them.
    module TestHelpers
      # Generated once per process: RSA key generation is slow.
      def self.key
        @key ||= OpenSSL::PKey::RSA.generate(2048)
      end

      # Webhook verification trusts TestHelpers.key (and only it) inside the block.
      def with_waffo_webhook_key(key = TestHelpers.key)
        config = Waffo::Pancake.configuration
        previous = config.webhook_public_key
        config.webhook_public_key = key.public_key
        yield
      ensure
        config.webhook_public_key = previous
      end

      # `t=<ms>,v1=<signature>` over the body, as Waffo sends it.
      def waffo_webhook_signature(body, at: Time.now, key: TestHelpers.key)
        timestamp = (at.to_f * 1000).to_i
        signature = Base64.strict_encode64(key.sign(OpenSSL::Digest::SHA256.new, "#{timestamp}.#{body}"))
        "t=#{timestamp},v1=#{signature}"
      end

      # Headers for posting `body` (a String) to a webhook endpoint.
      def waffo_webhook_headers(body, **options)
        { "CONTENT_TYPE" => "application/json", Webhook::SIGNATURE_HEADER => waffo_webhook_signature(body, **options) }
      end

      # A webhook envelope in Waffo's shape. `mode` and `store_id` default to the configuration.
      def waffo_webhook_event(event_type, data: {}, id: SecureRandom.uuid, mode: nil, store_id: nil)
        config = Waffo::Pancake.configuration
        {
          "id" => id,
          "timestamp" => Time.now.utc.iso8601,
          "eventType" => event_type,
          "eventId" => "evt_#{SecureRandom.hex(8)}",
          "storeId" => store_id || config.store_id || "STO_test",
          "storeName" => "Test store",
          "mode" => mode || config.environment || "test",
          "data" => data
        }
      end

      # Waffo::Pancake.client is `client` inside the block. Yields the client.
      def with_fake_waffo_client(client = FakeClient.new)
        previous = Waffo::Pancake.instance_variable_get(:@client)
        Waffo::Pancake.client = client
        yield client
      ensure
        Waffo::Pancake.client = previous
      end

      # Stands in for Waffo::Pancake::Client. Answers subscription_order from `orders`, moves
      # an order's status on cancel / reactivate the way Waffo does, and records every call
      # in `calls` as [method, arguments]. Set `fail_with` to an error to make calls raise it.
      class FakeClient
        attr_reader :orders, :calls
        attr_accessor :fail_with, :checkout_url

        def initialize(orders = {})
          @orders = orders.transform_keys(&:to_s)
          @calls = []
          @checkout_url = "https://pancake.waffo.ai/store/test/checkout/cs_test"
        end

        def subscription_order(order_id)
          record(:subscription_order, order_id)
          order = @orders[order_id.to_s]
          order && order.dup
        end

        def create_checkout_session(**params)
          record(:create_checkout_session, params)
          { "sessionId" => "cs_test", "checkoutUrl" => checkout_url, "expiresAt" => (Time.now + 2700).utc.iso8601 }
        end

        def create_authenticated_checkout(**params)
          record(:create_authenticated_checkout, params)
          { "sessionId" => "cs_test", "checkoutUrl" => "#{checkout_url}#token=test_token", "token" => "test_token",
            "expiresAt" => (Time.now + 2700).utc.iso8601 }
        end

        def cancel_subscription(order_id)
          record(:cancel_subscription, order_id)
          change_status(order_id, "canceling")
        end

        def reactivate_subscription(order_id)
          record(:reactivate_subscription, order_id)
          change_status(order_id, "active")
        end

        def graphql(query, variables = {})
          record(:graphql, query, variables)
          {}
        end

        def action(path, params)
          record(:action, path, params)
          {}
        end

        def called?(name) = calls.any? { |call| call.first == name }

        private
          def record(name, *arguments)
            calls << [name, *arguments]
            raise fail_with if fail_with
          end

          def change_status(order_id, status)
            @orders[order_id.to_s]&.merge!("status" => status)
            { "orderId" => order_id, "status" => status }
          end
      end
    end
  end
end
