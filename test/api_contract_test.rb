# frozen_string_literal: true

require "test_helper"

# Pins every action method to its documented path and body. A row here is the check that a method
# sends what https://docs.waffo.ai says, and API_METHODS below fails when a new method has no row.
class ApiContractTest < Minitest::Test
  AMOUNT = { amount: "9.99", currency: "USD" }.freeze
  PRICES = { "USD" => { amount: "9.99", taxCategory: "saas" } }.freeze
  JSON_AMOUNT = { "amount" => "9.99", "currency" => "USD" }.freeze
  JSON_PRICES = { "USD" => { "amount" => "9.99", "taxCategory" => "saas" } }.freeze

  # method, positional and keyword arguments, path, expected JSON body
  CONTRACT = [
    [:create_checkout_session, [], { product_id: "P", currency: "USD", buyer_email: "a@example.com" },
     "checkout/create-session", { "productId" => "P", "currency" => "USD", "buyerEmail" => "a@example.com" }],
    [:create_plan_change_session, [], { origin_order_id: "O", product_id: "P", currency: "USD" },
     "checkout/create-session", { "originOrderId" => "O", "productId" => "P", "currency" => "USD" }],
    [:cancel_subscription, ["O"], {}, "subscription-order/cancel-order", { "orderId" => "O" }],
    [:cancel_subscription, ["O"], { cancel_reason: "too_expensive", cancel_comment: "c" },
     "subscription-order/cancel-order", { "orderId" => "O", "cancelReason" => "too_expensive", "cancelComment" => "c" }],
    [:reactivate_subscription, ["O"], {}, "subscription-order/reactivate-order", { "orderId" => "O" }],
    [:cancel_onetime_order, ["O"], {}, "onetime-order/cancel-order", { "orderId" => "O" }],
    [:create_refund_ticket, [], { payment_id: "PAY", reason: "r", requested_amount: AMOUNT },
     "refund-ticket/create-ticket", { "paymentId" => "PAY", "reason" => "r", "requestedAmount" => JSON_AMOUNT }],
    [:resubmit_refund_ticket, [], { ticket_id: "T", reason: "r", requested_amount: AMOUNT },
     "refund-ticket/resubmit-ticket", { "ticketId" => "T", "reason" => "r", "requestedAmount" => JSON_AMOUNT }],

    [:create_store, [], { name: "S" }, "store/create-store", { "name" => "S" }],
    [:update_store, [], { id: "S", name: "N" }, "store/update-store", { "id" => "S", "name" => "N" }],
    [:delete_store, [], { id: "S" }, "store/delete-store", { "id" => "S" }],
    [:add_store_merchant, [], { store_id: "S", email: "a@example.com", role: "member" },
     "store-merchant/add-merchant", { "storeId" => "S", "email" => "a@example.com", "role" => "member" }],
    [:remove_store_merchant, [], { store_id: "S", merchant_id: "M" },
     "store-merchant/remove-merchant", { "storeId" => "S", "merchantId" => "M" }],
    [:update_store_merchant_role, [], { store_id: "S", merchant_id: "M", role: "admin" },
     "store-merchant/update-role", { "storeId" => "S", "merchantId" => "M", "role" => "admin" }],
    [:add_webhook, [], { store_id: "S", url: "u", events: ["e"], test_mode: true },
     "store/add-webhook", { "storeId" => "S", "channel" => "http", "url" => "u", "events" => ["e"], "testMode" => true }],
    [:update_webhook, [], { id: "W", url: "u" }, "store/update-webhook", { "id" => "W", "url" => "u" }],
    [:remove_webhook, [], { id: "W" }, "store/remove-webhook", { "id" => "W" }],
    [:add_notification_recipient, [], { store_id: "S", email: "a@example.com" },
     "store-notification-recipient/add-recipient", { "storeId" => "S", "email" => "a@example.com" }],
    [:update_notification_recipient, [], { store_id: "S", recipient_id: "R", preferences: { notifyChargeback: false } },
     "store-notification-recipient/update-recipient",
     { "storeId" => "S", "recipientId" => "R", "preferences" => { "notifyChargeback" => false } }],
    [:remove_notification_recipient, [], { store_id: "S", recipient_id: "R" },
     "store-notification-recipient/remove-recipient", { "storeId" => "S", "recipientId" => "R" }],

    [:create_subscription_product, [], { store_id: "S", name: "N", billing_period: "monthly", prices: PRICES },
     "subscription-product/create-product",
     { "storeId" => "S", "name" => "N", "billingPeriod" => "monthly", "prices" => JSON_PRICES }],
    [:update_subscription_product, [], { id: "P", name: "N" },
     "subscription-product/update-product", { "id" => "P", "name" => "N" }],
    [:publish_subscription_product, [], { id: "P" }, "subscription-product/publish-product", { "id" => "P" }],
    [:update_subscription_product_status, [], { id: "P", status: "inactive" },
     "subscription-product/update-status", { "id" => "P", "status" => "inactive" }],
    [:create_onetime_product, [], { store_id: "S", name: "N", prices: PRICES },
     "onetime-product/create-product", { "storeId" => "S", "name" => "N", "prices" => JSON_PRICES }],
    [:update_onetime_product, [], { id: "P", name: "N" }, "onetime-product/update-product", { "id" => "P", "name" => "N" }],
    [:publish_onetime_product, [], { id: "P" }, "onetime-product/publish-product", { "id" => "P" }],
    [:update_onetime_product_status, [], { id: "P", status: "active" },
     "onetime-product/update-status", { "id" => "P", "status" => "active" }],
    [:create_subscription_product_group, [], { store_id: "S", name: "G", product_ids: ["P"] },
     "subscription-product-group/create-group", { "storeId" => "S", "name" => "G", "productIds" => ["P"] }],
    [:update_subscription_product_group, [], { id: "G", name: "N" },
     "subscription-product-group/update-group", { "id" => "G", "name" => "N" }],
    [:delete_subscription_product_group, [], { id: "G" }, "subscription-product-group/delete-group", { "id" => "G" }],
    [:publish_subscription_product_group, [], { id: "G" }, "subscription-product-group/publish-group", { "id" => "G" }],

    [:create_coupon, [], { store_id: "S", name: "C", discount: { type: "percentage", percentOff: 10 } },
     "coupon/create-coupon",
     { "storeId" => "S", "name" => "C", "discount" => { "type" => "percentage", "percentOff" => 10 } }],
    [:update_coupon, [], { id: "C", name: "N" }, "coupon/update-coupon", { "id" => "C", "name" => "N" }],
    [:deactivate_coupon, [], { id: "C" }, "coupon/deactivate-coupon", { "id" => "C" }],
    [:create_promotion_code, [], { coupon_id: "C", code: "SAVE" },
     "promotion-code/create-promotion-code", { "couponId" => "C", "code" => "SAVE" }],
    [:generate_promotion_codes, [], { coupon_id: "C", count: 5, prefix: "X" },
     "promotion-code/generate-promotion-codes", { "couponId" => "C", "count" => 5, "prefix" => "X" }],
    [:deactivate_promotion_code, [], { id: "PC" }, "promotion-code/deactivate-promotion-code", { "id" => "PC" }],
    [:scan_prompt, [], { prompt: "p", locale: "en" }, "verification/scan-prompt", { "prompt" => "p", "locale" => "en" }]
  ].freeze

  API_METHODS = [
    Waffo::Pancake::API::CustomerActions, Waffo::Pancake::API::StoreActions,
    Waffo::Pancake::API::ProductActions, Waffo::Pancake::API::PromotionActions
  ].flat_map(&:public_instance_methods).freeze

  def recording_client
    requests = []
    transport = lambda do |uri, headers, json|
      requests << { path: uri.path, headers: headers, body: JSON.parse(json) }
      [200, '{"data":{}}']
    end
    [Waffo::Pancake::Client.new(merchant_id: "MER_x", private_key: TestKeys::KEY, transport: transport), requests]
  end

  CONTRACT.each_with_index do |(name, positional, keywords, path, body), index|
    define_method(:"test_#{name}_#{index}_sends_the_documented_path_and_body") do
      client, requests = recording_client

      client.public_send(name, *positional, **keywords)

      assert_equal "/v1/actions/#{path}", requests.first[:path]
      assert_equal body, requests.first[:body]
    end

    define_method(:"test_#{name}_#{index}_passes_the_idempotency_key_as_a_header_only") do
      client, requests = recording_client

      client.public_send(name, *positional, **keywords, idempotency_key: "key_1")

      assert_equal "key_1", requests.first[:headers]["X-Idempotency-Key"]
      assert_equal body, requests.first[:body]
    end
  end

  def test_every_action_method_has_a_contract_row
    assert_empty API_METHODS - CONTRACT.map(&:first)
  end

  # Every path the documentation lists on 2026-11-04. The three that have no row are pinned in
  # requests_test.rb (issue-session-token) and customer_session_test.rb (create-order).
  def test_every_documented_path_has_a_method
    documented = %w[
      auth/issue-session-token checkout/create-session coupon/create-coupon coupon/deactivate-coupon
      coupon/update-coupon onetime-order/cancel-order onetime-order/create-order onetime-product/create-product
      onetime-product/publish-product onetime-product/update-product onetime-product/update-status
      promotion-code/create-promotion-code promotion-code/deactivate-promotion-code
      promotion-code/generate-promotion-codes refund-ticket/create-ticket refund-ticket/resubmit-ticket
      store-notification-recipient/add-recipient store-notification-recipient/remove-recipient
      store-notification-recipient/update-recipient store/add-webhook store/create-store store/delete-store
      store/remove-webhook store/update-store store/update-webhook subscription-order/cancel-order
      subscription-order/create-order subscription-order/reactivate-order subscription-product-group/create-group
      subscription-product-group/delete-group subscription-product-group/publish-group
      subscription-product-group/update-group subscription-product/create-product
      subscription-product/publish-product subscription-product/update-product subscription-product/update-status
      verification/scan-prompt
    ]
    pinned_elsewhere = %w[auth/issue-session-token onetime-order/create-order subscription-order/create-order]

    assert_equal 37, documented.size
    assert_empty documented - pinned_elsewhere - CONTRACT.map { |row| row[3] }
  end
end
