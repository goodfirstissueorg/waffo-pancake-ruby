# frozen_string_literal: true

require_relative "live_helper"

# Writes, all on the temporary store. See live_helper.rb for what is left out and why.
class LiveActionsTest < LiveAPI::TestCase
  include LiveAPI

  # --- Stores --------------------------------------------------------------------------

  def test_store_lifecycle
    id = client.create_store(name: LiveAPI.unique_name).dig("store", "id")

    renamed = LiveAPI.unique_name
    assert_equal renamed, client.update_store(id: id, name: renamed).dig("store", "name")
    assert_nil client.update_store(id: id, logo: Waffo::Pancake::NULL).dig("store", "logo")
    assert_equal renamed, client.store(id).fetch("name")

    client.delete_store(id: id)
    deleted = true
    assert_nil client.store(id)
  ensure
    client.delete_store(id: id) if id && !deleted
  end

  def test_warnings_reach_the_result
    result = client.update_store(id: store_id, webhook_settings: {})

    refute_empty result.fetch("warnings")
  end

  # --- Store members -------------------------------------------------------------------

  def test_store_merchant_routes_accept_an_api_key
    unknown = "MER_0000000000000000000000"

    assert_route_accepts_credential { client.remove_store_merchant(store_id: store_id, merchant_id: unknown) }
    assert_route_accepts_credential do
      client.update_store_merchant_role(store_id: store_id, merchant_id: unknown, role: "member")
    end
  end

  # --- Products ------------------------------------------------------------------------

  def test_onetime_product_lifecycle
    product = onetime_product
    id = product.fetch("id")

    client.update_onetime_product(id: id, name: LiveAPI.unique_name, prices: PRICES)
    assert_equal 2, client.onetime_product_versions(id).size
    assert_equal "9.99", client.onetime_product(id).dig("prices", 0, "priceInfo", "amount")
    assert_equal "inactive", client.update_onetime_product_status(id: id, status: "inactive").dig("product", "status")
    assert_equal "active", client.update_onetime_product_status(id: id, status: "active").dig("product", "status")
  end

  def test_subscription_product_lifecycle
    id = subscription_product.fetch("id")

    client.update_subscription_product(id: id, name: LiveAPI.unique_name, billing_period: "monthly", prices: PRICES)
    assert_equal 2, client.subscription_product_versions(id).size
    assert_equal "monthly", client.subscription_product(id).fetch("billingPeriod")
    assert_equal "inactive",
                 client.update_subscription_product_status(id: id, status: "inactive").dig("product", "status")
  end

  def test_product_group_lifecycle_runs_in_test_mode
    product_id = subscription_product.fetch("id")
    id = client.create_subscription_product_group(store_id: store_id, name: LiveAPI.unique_name,
                                                  product_ids: [product_id]).dig("group", "id")

    assert_equal "test", client.subscription_product_group(id).fetch("environment"),
                 "the key must be a test-mode key"
    renamed = LiveAPI.unique_name
    assert_equal renamed, client.update_subscription_product_group(id: id, name: renamed).dig("group", "name")
    client.delete_subscription_product_group(id: id)
    assert_nil client.subscription_product_group(id)
  end

  # --- Webhooks and recipients ---------------------------------------------------------

  def test_webhook_lifecycle
    id = client.add_webhook(store_id: store_id, url: "https://example.com/hook", events: ["order.completed"],
                            test_mode: true).dig("webhook", "id")

    assert_equal "abcdefgh12345678",
                 client.update_webhook(id: id, secret: "abcdefgh12345678").dig("webhook", "secret")
    assert_nil client.update_webhook(id: id, secret: Waffo::Pancake::NULL).dig("webhook", "secret")
    assert_includes client.store_webhooks(store_id: store_id).map { |webhook| webhook["id"] }, id
    client.remove_webhook(id: id)
    refute_includes client.store_webhooks(store_id: store_id).map { |webhook| webhook["id"] }, id
  end

  def test_notification_recipient_lifecycle
    email = "#{LiveAPI.unique_name}@example.com"
    id = client.add_notification_recipient(store_id: store_id, email: email).dig("recipient", "id")

    assert_includes client.notification_recipients(store_id: store_id).map { |recipient| recipient["email"] }, email
    updated = client.update_notification_recipient(store_id: store_id, recipient_id: id,
                                                   preferences: { notifyChargeback: false })
    assert_equal false, updated.dig("recipient", "preferences", "notifyChargeback")
    assert_equal true, client.remove_notification_recipient(store_id: store_id, recipient_id: id).fetch("removed")
  end

  # --- Promotions ----------------------------------------------------------------------

  def test_coupon_and_promotion_code_lifecycle
    coupon = client.create_coupon(store_id: store_id, name: LiveAPI.unique_name,
                                  discount: { type: "percentage", percentOff: 10 }).fetch("coupon")
    id = coupon.fetch("id")

    assert_includes client.coupons(store_id: store_id, filter: { status: { eq: "active" } })
      .map { |row| row["id"] }, id
    renamed = LiveAPI.unique_name
    assert_equal renamed, client.update_coupon(id: id, name: renamed).dig("coupon", "name")

    code = client.create_promotion_code(coupon_id: id).fetch("promotionCode")
    assert_equal 2, client.generate_promotion_codes(coupon_id: id, count: 2).fetch("promotionCodes").size
    assert_equal 3, client.promotion_codes(coupon_id: id).size
    assert_equal 3, client.promotion_codes_count(coupon_id: id)
    assert_equal "inactive", client.deactivate_promotion_code(id: code.fetch("id")).dig("promotionCode", "status")
    assert_equal "inactive", client.deactivate_coupon(id: id).dig("coupon", "status")
  end

  def test_scan_prompt
    assert_equal "allow", client.scan_prompt(prompt: "a cat on a mat").fetch("action")
  end

  # --- Checkout, sessions and credentials ----------------------------------------------

  def test_idempotency_key_replays_the_session
    product_id = onetime_product.fetch("id")
    key = "sdk-live-#{SecureRandom.hex(8)}"

    first = client.create_checkout_session(product_id: product_id, currency: "USD", idempotency_key: key)
    second = client.create_checkout_session(product_id: product_id, currency: "USD", idempotency_key: key)
    other = client.create_checkout_session(product_id: product_id, currency: "USD")

    assert_equal first.fetch("sessionId"), second.fetch("sessionId")
    refute_equal first.fetch("sessionId"), other.fetch("sessionId")
  end

  def test_store_slug_checkout
    product_id = onetime_product.fetch("id")
    slug = client.store(store_id, fields: "slug").fetch("slug")
    storefront = Waffo::Pancake::StoreCheckout.new(store_slug: slug, environment: "test")

    assert storefront.create_checkout_session(product_id: product_id, currency: "USD").key?("sessionId")
  end

  def test_customer_portal_link
    assert_includes client.create_customer_portal_link(buyer_identity: "sdk-live", store_id: store_id)
      .fetch("portalUrl"), "#token="
  end

  def test_onetime_order_through_a_customer_session
    product_id = onetime_product.fetch("id")
    token = client.issue_session_token(buyer_identity: "sdk-live", product_id: product_id).fetch("token")
    customer = client.customer(token, environment: "test")
    refute_includes customer.inspect, token

    session = customer.create_checkout_session(product_id: product_id, currency: "USD")
    order = customer.create_onetime_order(checkout_session_id: session.fetch("sessionId"), billing_detail: BILLING,
                                          language: "en", buyer_email: "sdk-live@example.com")
    assert_includes order.keys, "checkoutUrl"

    order_id = LiveAPI.pending_order_id(client.onetime_orders(store_id: store_id, fields: "id status"))
    assert_equal "canceled", customer.cancel_onetime_order(order_id).fetch("status")
    assert_equal "canceled", client.onetime_order(order_id).fetch("status")
  end

  def test_subscription_order_through_a_customer_session_and_cancel_with_an_api_key
    product_id = subscription_product.fetch("id")
    token = client.issue_session_token(buyer_identity: "sdk-live", product_id: product_id).fetch("token")
    customer = client.customer(token, environment: "test")

    session = customer.create_checkout_session(product_id: product_id, currency: "USD")
    order = customer.create_subscription_order(checkout_session_id: session.fetch("sessionId"), billing_detail: BILLING,
                                               language: "en", buyer_email: "sdk-live@example.com")
    assert_includes order.keys, "checkoutUrl"

    order_id = LiveAPI.pending_order_id(client.subscription_orders(store_id: store_id, fields: "id status"))
    assert_equal "canceled", client.cancel_subscription(order_id).fetch("status")
  end

  def test_customer_session_reads_graphql
    product_id = onetime_product.fetch("id")
    token = client.issue_session_token(buyer_identity: "sdk-live", product_id: product_id).fetch("token")

    assert_kind_of Array, client.customer(token, environment: "test").graphql("{ onetimeOrders(limit: 1) { id } }")
      .fetch("onetimeOrders")
  end

  def test_customer_session_routes_refused_to_an_api_key_are_open_to_a_token
    token = client.issue_session_token(buyer_identity: "sdk-live", store_id: store_id).fetch("token")
    customer = client.customer(token, environment: "test")

    assert_route_accepts_credential { customer.reactivate_subscription(LiveAPI::UNKNOWN_ORDER) }
    assert_route_accepts_credential { customer.cancel_onetime_order(LiveAPI::UNKNOWN_ORDER) }
  end

  # When this fails, Waffo has opened the routes: the README and API::CustomerActions can then
  # stop sending callers to a customer session.
  def test_the_gateway_refuses_an_api_key_on_these_routes
    [-> { client.reactivate_subscription(LiveAPI::UNKNOWN_ORDER) },
     -> { client.cancel_onetime_order(LiveAPI::UNKNOWN_ORDER) }].each do |call|
      assert_equal 401, assert_raises(Waffo::Pancake::Rejected, &call).status
    end
  end

  def test_refund_ticket_routes_accept_an_api_key
    amount = { amount: "1.00", currency: "USD" }

    assert_route_accepts_credential do
      client.create_refund_ticket(payment_id: LiveAPI::UNKNOWN_PAYMENT, reason: "sdk live", requested_amount: amount)
    end
    assert_route_accepts_credential do
      client.resubmit_refund_ticket(ticket_id: "TKT_0000000000000000000000", reason: "sdk live", requested_amount: amount)
    end
  end

  def test_plan_change_reaches_the_order_lookup
    product_id = subscription_product.fetch("id")

    error = assert_route_accepts_credential do
      client.create_authenticated_plan_change(origin_order_id: LiveAPI::UNKNOWN_ORDER, product_id: product_id,
                                              currency: "USD", buyer_identity: "sdk-live")
    end
    refute_match(/Product not found/, error.message)
  end
end
