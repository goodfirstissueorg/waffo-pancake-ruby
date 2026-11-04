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

  def test_fake_client_has_every_api_method
    api = Waffo::Pancake::Client.public_instance_methods(false) + [
      Waffo::Pancake::API::CustomerActions, Waffo::Pancake::API::StoreActions, Waffo::Pancake::API::ProductActions,
      Waffo::Pancake::API::PromotionActions, Waffo::Pancake::API::Queries
    ].flat_map(&:public_instance_methods)
    identity = %i[merchant_id base_url store_id environment inspect]

    assert_empty(api.uniq - identity - FakeClient.public_instance_methods)
  end

  def test_fake_client_answers_new_methods_by_their_kind
    client = FakeClient.new

    assert_equal({}, client.create_store(name: "S"))
    assert_equal [], client.coupons
    assert_equal 0, client.coupons_count
    assert_nil client.coupon("C")
    assert_equal 0, client.webhook_deliveries_count
    assert_equal [:create_store, { name: "S" }], client.calls.first
  end

  def test_fake_client_records_cancel_with_and_without_options
    client = FakeClient.new

    client.cancel_subscription("ORD_1")
    client.cancel_subscription("ORD_2", cancel_reason: "r")

    assert_equal [[:cancel_subscription, "ORD_1"], [:cancel_subscription, "ORD_2", { cancel_reason: "r" }]], client.calls
  end

  def test_fake_client_customer_records_and_answers_as_itself
    client = FakeClient.new

    session = client.customer("tok", environment: "test")
    session.create_onetime_order(checkout_session_id: "cs", billing_detail: {}, language: "en")

    assert_same client, session
    assert_equal [:customer, "tok", { environment: "test" }], client.calls.first
    assert client.called?(:create_onetime_order)
  end

  def test_fake_client_action_takes_positional_and_named_params
    client = FakeClient.new

    client.action("/p", { a: 1 }, idempotency_key: "k")

    assert_equal [:action, "/p", { a: 1, idempotency_key: "k" }], client.calls.first
  end

  def test_fake_client_answers_portal_links_and_deliveries
    client = FakeClient.new
    client.deliveries = [{ "id" => "dlv_1", "status" => "failed" }, { "id" => "dlv_2", "status" => "success" }]

    assert_match(/#token=test_token\z/, client.create_customer_portal_link(buyer_identity: "u")["portalUrl"])
    assert_equal ["dlv_1"], client.webhook_deliveries(status: :failed).map { |delivery| delivery["id"] }
    assert_equal 2, client.webhook_deliveries.size
  end
end
