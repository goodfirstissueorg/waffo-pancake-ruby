# frozen_string_literal: true

require "test_helper"
require "waffo/pancake/test_helpers"

class TestHelpersTest < Minitest::Test
  include Waffo::Pancake::TestHelpers

  def teardown = Waffo::Pancake.reset!

  def test_signed_headers_verify_against_the_test_key
    body = JSON.generate(waffo_webhook_event("subscription.activated", data: { orderId: "ORD_1" }))

    event = with_waffo_webhook_key do
      Waffo::Pancake.verify_webhook(body, waffo_webhook_headers(body)[Waffo::Pancake::Webhook::SIGNATURE_HEADER])
    end

    assert_equal "subscription.activated", event["eventType"]
    assert_nil Waffo::Pancake.configuration.webhook_public_key, "the key is put back after the block"
  end

  def test_fake_client_records_calls_and_moves_order_status
    with_fake_waffo_client(FakeClient.new("ORD_1" => { "status" => "active" })) do |client|
      assert_same client, Waffo::Pancake.client

      assert_equal({ "orderId" => "ORD_1", "status" => "canceling" }, Waffo::Pancake.client.cancel_subscription("ORD_1"))
      assert_equal "canceling", Waffo::Pancake.client.subscription_order("ORD_1")["status"]
      assert client.called?(:cancel_subscription)
      assert_equal [:subscription_order, "ORD_1"], client.calls.last
    end
  end

  def test_fake_client_raises_what_it_is_told_to
    client = FakeClient.new
    client.fail_with = Waffo::Pancake::Unavailable.new("down")

    assert_raises(Waffo::Pancake::Unavailable) { client.create_authenticated_checkout(product_id: "PROD_1") }
    assert_equal [[:create_authenticated_checkout, { product_id: "PROD_1" }]], client.calls
  end
end
