# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < Minitest::Test
  def teardown = Waffo::Pancake.reset!

  def test_starts_from_the_environment_variables
    with_env("WAFFO_MERCHANT_ID" => "MER_env", "WAFFO_STORE_ID" => "STO_env", "WAFFO_ENVIRONMENT" => " Prod ") do
      Waffo::Pancake.reset!
      config = Waffo::Pancake.configuration

      assert_equal "MER_env", config.merchant_id
      assert_equal "STO_env", config.store_id
      assert_equal "prod", config.environment
    end
  end

  def test_refuses_an_unknown_environment
    assert_raises(Waffo::Pancake::ConfigurationError) { Waffo::Pancake.configuration.environment = "production" }
  end

  def test_the_shared_client_follows_configure
    Waffo::Pancake.configure do |config|
      config.merchant_id = "MER_one"
      config.private_key = TestKeys::KEY.private_to_pem
    end
    first = Waffo::Pancake.client
    assert_same first, Waffo::Pancake.client
    assert_equal "MER_one", first.merchant_id

    Waffo::Pancake.configure { |config| config.merchant_id = "MER_two" }
    assert_equal "MER_two", Waffo::Pancake.client.merchant_id
  end

  def test_the_shared_client_needs_credentials
    with_env("WAFFO_MERCHANT_ID" => nil, "WAFFO_PRIVATE_KEY" => nil) do
      Waffo::Pancake.reset!
      refute Waffo::Pancake.configuration.configured?
      assert_raises(Waffo::Pancake::ConfigurationError) { Waffo::Pancake.client }
    end
  end

  def test_verify_webhook_uses_the_configured_key_and_tolerance
    body = JSON.generate({ id: "evt_1", eventType: "refund.succeeded" })
    stale = TestKeys.webhook_header(body, at: Time.now - 3600)
    Waffo::Pancake.configure { |config| config.webhook_public_key = TestKeys::KEY.public_to_pem }

    assert_raises(Waffo::Pancake::InvalidSignature) { Waffo::Pancake.verify_webhook(body, stale) }

    Waffo::Pancake.configure { |config| config.webhook_tolerance = 0 }
    assert_equal "evt_1", Waffo::Pancake.verify_webhook(body, stale)["id"]
  end

  def test_reports_requests_and_webhook_checks_to_the_instrumenter
    events = []
    instrumenter = Object.new
    instrumenter.define_singleton_method(:instrument) do |name, payload, &block|
      result = block.call(payload)
      events << [name, payload]
      result
    end
    transport = ->(*) { [200, JSON.generate({ data: { orderId: "ORD_1", status: "active" } })] }
    client = Waffo::Pancake::Client.new(merchant_id: "MER_x", private_key: TestKeys::KEY, instrumenter: instrumenter,
                                        transport: transport)

    client.reactivate_subscription("ORD_1")
    assert_equal ["request.waffo_pancake", { method: "POST", path: "/v1/actions/subscription-order/reactivate-order",
                                             status: 200 }], events.last

    Waffo::Pancake.configure do |config|
      config.instrumenter = instrumenter
      config.webhook_public_key = TestKeys::KEY.public_to_pem
      config.environment = "test"
    end
    body = JSON.generate({ id: "evt_2", eventType: "subscription.canceled", mode: "test" })
    Waffo::Pancake.verify_webhook(body, TestKeys.webhook_header(body))
    assert_equal ["verify_webhook.waffo_pancake",
                  { environment: "test", event_id: "evt_2", event_type: "subscription.canceled", mode: "test" }], events.last
  end

  def test_no_instrumenter_without_active_support
    refute defined?(ActiveSupport), "the core tests run without ActiveSupport loaded"
    assert_nil Waffo::Pancake.configuration.instrumenter
  end

  private
    def with_env(vars)
      previous = vars.keys.to_h { |key| [key, ENV[key]] }
      vars.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
      yield
    ensure
      previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end
end
