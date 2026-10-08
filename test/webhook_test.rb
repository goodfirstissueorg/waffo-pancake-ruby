# frozen_string_literal: true

require "test_helper"

class WebhookTest < Minitest::Test
  BODY = JSON.generate({ id: "evt_1", eventType: "subscription.activated", data: { orderId: "ORD_1" } })
  KEY = TestKeys::KEY

  def verify(body = BODY, header = TestKeys.webhook_header(BODY), **options)
    Waffo::Pancake::Webhook.verify(body, header, public_key: KEY.public_to_pem, **options)
  end

  def test_returns_the_parsed_event
    assert_equal "subscription.activated", verify["eventType"]
  end

  def test_refuses_a_changed_body_or_another_key
    other = OpenSSL::PKey::RSA.generate(2048)

    assert_raises(Waffo::Pancake::InvalidSignature) { verify("#{BODY} ") }
    assert_raises(Waffo::Pancake::InvalidSignature) { verify(BODY, TestKeys.webhook_header(BODY, key: other)) }
  end

  def test_refuses_stale_and_future_timestamps_unless_tolerance_is_zero
    stale = TestKeys.webhook_header(BODY, at: Time.now - (46 * 60))
    future = TestKeys.webhook_header(BODY, at: Time.now + 120)

    assert_raises(Waffo::Pancake::InvalidSignature) { verify(BODY, stale) }
    assert_raises(Waffo::Pancake::InvalidSignature) { verify(BODY, future) }
    assert_equal "evt_1", verify(BODY, stale, tolerance: 0)["id"]
  end

  def test_refuses_missing_and_malformed_headers
    [nil, "", "v1=abc", "t=123", "t=abc,v1=abc", "t=#{(Time.now.to_f * 1000).to_i},v1=%%%"].each do |header|
      assert_raises(Waffo::Pancake::InvalidSignature) { verify(BODY, header) }
    end
  end

  def test_environment_keys_come_from_env_before_the_built_in_ones
    pem = KEY.public_to_pem.gsub("\n", "\\n")
    with_env("WAFFO_WEBHOOK_TEST_PUBLIC_KEY" => pem) do
      event = Waffo::Pancake::Webhook.verify(BODY, TestKeys.webhook_header(BODY), environment: "test")
      assert_equal "evt_1", event["id"]
      assert_raises(Waffo::Pancake::InvalidSignature) do
        Waffo::Pancake::Webhook.verify(BODY, TestKeys.webhook_header(BODY), environment: "prod")
      end
    end
  end

  def test_without_an_environment_it_tries_prod_then_test
    with_env("WAFFO_WEBHOOK_TEST_PUBLIC_KEY" => KEY.public_to_pem) do
      assert_equal "evt_1", Waffo::Pancake::Webhook.verify(BODY, TestKeys.webhook_header(BODY))["id"]
    end
  end

  def test_built_in_keys_load
    %w[test prod].each do |environment|
      with_env("WAFFO_WEBHOOK_PUBLIC_KEY" => nil, "WAFFO_WEBHOOK_#{environment.upcase}_PUBLIC_KEY" => nil) do
        assert_equal 2048, Waffo::Pancake::Webhook.public_key_for(environment).n.num_bits
      end
    end
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
