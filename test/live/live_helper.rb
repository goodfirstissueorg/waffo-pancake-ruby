# frozen_string_literal: true

# Tests against the real API, run by `rake test:live` and never by `rake test`.
#
# Invariants, because the merchant behind the key may also have real stores:
# - WAFFO_ENVIRONMENT must be "test" and WAFFO_LIVE must be set, or nothing runs.
# - WAFFO_STORE_ID is only read. Every write goes to a temporary store this run creates.
# - publish_* is never called: it creates production data that a test key cannot remove, and the
#   temporary store could then not be deleted.
#
# shortcut: a killed or canceled run skips clean_up and leaves its store, named sdk-live-<hex>, behind; delete it by hand until the API offers an expiring store.
require "securerandom"
require "test_helper"

module LiveAPI
  NAME_PREFIX = "sdk-live"
  BUYER = "sdk-live"
  # Well-formed ids that exist nowhere, for checks that a route accepts a credential.
  UNKNOWN_ORDER = "ORD_0000000000000000000000"
  UNKNOWN_PAYMENT = "PAY_0000000000000000000000"
  PRICES = { "USD" => { amount: "9.99", taxCategory: "saas" } }.freeze
  BILLING = { country: "US", isBusiness: false, postcode: "94105", state: "CA" }.freeze

  # A connection that never opened sent nothing, and a GraphQL read changes nothing, so a retry of
  # either cannot repeat a write. These network failures say nothing about the SDK. Any other
  # failure of an action still fails the test, because the write may have reached Waffo.
  #
  # Not a SimpleDelegator: Delegator removes Kernel#raise, so a `raise` here would enter
  # method_missing again and recurse until the stack overflows.
  class RetriedClient
    ATTEMPTS = 3
    PAUSE = 2

    def initialize(target)
      @target = target
    end

    def inspect = @target.inspect

    def respond_to_missing?(name, include_private = false) = @target.respond_to?(name, include_private) || super

    def method_missing(name, ...)
      attempt = 0
      begin
        attempt += 1
        result = @target.public_send(name, ...)
        result.is_a?(Waffo::Pancake::CustomerSession) ? RetriedClient.new(result) : result
      rescue Waffo::Pancake::Unavailable => e
        retryable = e.message.include?("Net::OpenTimeout") || e.message.include?("/v1/graphql")
        raise unless retryable && attempt < ATTEMPTS

        warn "RETRY #{name}: #{e.message} (attempt #{attempt})"
        sleep PAUSE
        retry
      end
    end
  end

  module_function

  def enabled? = ENV["WAFFO_LIVE"] == "1" && ENV["WAFFO_ENVIRONMENT"] == "test"

  def client = @client ||= RetriedClient.new(Waffo::Pancake::Client.new)

  def unique_name = "#{NAME_PREFIX}-#{SecureRandom.hex(4)}"

  # Created on first use and deleted when the run ends.
  def temporary_store
    @temporary_store ||= client.create_store(name: unique_name).fetch("store")
  end

  def clean_up
    return unless @temporary_store

    # remove_store reads the state again on each pass, so repeating it after any failure is safe.
    attempts = 0
    begin
      attempts += 1
      remove_store(@temporary_store.fetch("id"))
    rescue Waffo::Pancake::Unavailable
      retry if attempts < RetriedClient::ATTEMPTS
      raise
    end
  rescue Waffo::Pancake::Error => e
    warn "LEFTOVER: temporary store #{@temporary_store["id"]} was not deleted: #{e.message}"
  end

  # Waffo refuses to delete a store that still has pending orders or active products.
  def remove_store(store_id)
    cancel_pending_orders(store_id)
    client.onetime_products(store_id: store_id, fields: "id status").each do |product|
      client.update_onetime_product_status(id: product["id"], status: "inactive") if product["status"] == "active"
    end
    client.subscription_products(store_id: store_id, fields: "id status").each do |product|
      client.update_subscription_product_status(id: product["id"], status: "inactive") if product["status"] == "active"
    end
    client.delete_store(id: store_id)
  end

  def pending_order_id(orders)
    orders.find { |order| order["status"] == "pending" }&.fetch("id")
  end

  # The gateway refuses an API key on cancel-order for one-time orders, so that one needs a token.
  def cancel_pending_orders(store_id)
    client.subscription_orders(store_id: store_id, fields: "id status").each do |order|
      client.cancel_subscription(order["id"]) if order["status"] == "pending"
    end
    pending = client.onetime_orders(store_id: store_id, fields: "id status").select { |order| order["status"] == "pending" }
    return if pending.empty?

    token = client.issue_session_token(buyer_identity: BUYER, store_id: store_id).fetch("token")
    customer = client.customer(token, environment: "test")
    pending.each { |order| customer.cancel_onetime_order(order["id"]) }
  end

  class TestCase < Minitest::Test
    def setup
      skip "set WAFFO_LIVE=1 and WAFFO_ENVIRONMENT=test to call the real API" unless LiveAPI.enabled?
    end

    private
      def client = LiveAPI.client

      def store_id = LiveAPI.temporary_store.fetch("id")

      def onetime_product
        client.create_onetime_product(store_id: store_id, name: LiveAPI.unique_name, prices: PRICES).fetch("product")
      end

      def subscription_product
        client.create_subscription_product(store_id: store_id, name: LiveAPI.unique_name, billing_period: "monthly",
                                           prices: PRICES).fetch("product")
      end

      # The gateway answers 401 when the route does not take the credential, so any other refusal
      # proves that the route took it and went on to look at the request.
      def assert_route_accepts_credential
        error = assert_raises(Waffo::Pancake::Rejected) { yield }
        refute_equal 401, error.status, error.message
        error
      end
  end
end

Minitest.after_run { LiveAPI.clean_up if LiveAPI.enabled? }
