# frozen_string_literal: true

require "test_helper"

class CustomerSessionTest < Minitest::Test
  BILLING = { country: "US", isBusiness: false }.freeze

  def session_with(*responses, environment: "test", client_environment: nil)
    requests = []
    transport = lambda do |uri, headers, json|
      requests << { path: uri.path, headers: headers, body: JSON.parse(json) }
      responses.shift || [200, '{"data":{}}']
    end
    client = Waffo::Pancake::Client.new(merchant_id: "MER_x", private_key: TestKeys::KEY, transport: transport,
                                        environment: client_environment)
    [client.customer("tok_secret", environment: environment), requests]
  end

  def test_sends_the_token_and_the_environment_and_no_signature
    session, requests = session_with

    session.reactivate_subscription("ORD_1")

    headers = requests.first[:headers]
    assert_equal "Bearer tok_secret", headers["Authorization"]
    assert_equal "test", headers["X-Environment"]
    %w[X-Merchant-Id X-Signature X-Timestamp X-Store-Slug].each { |name| refute headers.key?(name), name }
  end

  def test_has_the_customer_actions
    session, requests = session_with

    session.cancel_onetime_order("ORD_1")
    session.cancel_subscription("ORD_2", cancel_reason: "r")
    session.create_refund_ticket(payment_id: "PAY", reason: "r", requested_amount: { amount: "1", currency: "USD" })
    session.create_plan_change_session(origin_order_id: "O", product_id: "P", currency: "USD")

    assert_equal %w[/v1/actions/onetime-order/cancel-order /v1/actions/subscription-order/cancel-order
                    /v1/actions/refund-ticket/create-ticket /v1/actions/checkout/create-session],
                 requests.map { |request| request[:path] }
  end

  def test_has_no_merchant_actions
    session, = session_with

    refute_respond_to session, :create_store
    refute_respond_to session, :issue_session_token
  end

  def test_create_orders
    session, requests = session_with

    session.create_onetime_order(checkout_session_id: "cs", billing_detail: BILLING, language: "en")
    session.create_subscription_order(checkout_session_id: "cs", billing_detail: BILLING, language: "en",
                                      user_terminal: "web", idempotency_key: "k")

    assert_equal "/v1/actions/onetime-order/create-order", requests[0][:path]
    assert_equal({ "checkoutSessionId" => "cs", "billingDetail" => { "country" => "US", "isBusiness" => false },
                   "language" => "en" }, requests[0][:body])
    assert_equal "/v1/actions/subscription-order/create-order", requests[1][:path]
    assert_equal "web", requests[1][:body]["userTerminal"]
    assert_equal "k", requests[1][:headers]["X-Idempotency-Key"]
  end

  def test_create_order_needs_a_language_before_it_calls_waffo
    session, requests = session_with

    [nil, "", " "].each do |language|
      assert_raises(ArgumentError) do
        session.create_onetime_order(checkout_session_id: "cs", billing_detail: BILLING, language: language)
      end
      assert_raises(ArgumentError) do
        session.create_subscription_order(checkout_session_id: "cs", billing_detail: BILLING, language: language)
      end
    end
    assert_empty requests
  end

  def test_graphql_uses_the_token
    session, requests = session_with([200, '{"data":{"me":null}}'])

    session.graphql("{ me { id } }")

    assert_equal "Bearer tok_secret", requests.first[:headers]["Authorization"]
  end

  def test_inspect_hides_the_token
    session, = session_with

    refute_includes session.inspect, "tok_secret"
    assert_includes session.inspect, "test"
  end

  def test_environment_defaults_to_the_client_and_is_normalized
    session, requests = session_with(client_environment: "prod", environment: "PROD")

    session.reactivate_subscription("ORD_1")

    assert_equal "prod", requests.first[:headers]["X-Environment"]
  end

  def test_an_unknown_or_missing_environment_is_refused
    [nil, "", "staging"].each do |environment|
      assert_raises(Waffo::Pancake::ConfigurationError, environment.inspect) { session_with(environment: environment) }
    end
  end

  def test_a_missing_token_is_refused
    client = Waffo::Pancake::Client.new(merchant_id: "M", private_key: TestKeys::KEY, environment: "test")

    [nil, "", " "].each do |token|
      assert_raises(Waffo::Pancake::ConfigurationError) { client.customer(token) }
    end
  end
end

class StoreCheckoutTest < Minitest::Test
  def storefront(**options)
    requests = []
    transport = lambda do |uri, headers, json|
      requests << { path: uri.path, headers: headers, body: JSON.parse(json) }
      [200, '{"data":{"sessionId":"cs"}}']
    end
    [Waffo::Pancake::StoreCheckout.new(store_slug: "my-store", environment: "test", transport: transport, **options),
     requests]
  end

  def test_sends_the_slug_and_the_environment_alone
    store, requests = storefront

    assert_equal "cs", store.create_checkout_session(product_id: "P", currency: "USD")["sessionId"]

    headers = requests.first[:headers]
    assert_equal "my-store", headers["X-Store-Slug"]
    assert_equal "test", headers["X-Environment"]
    %w[Authorization X-Merchant-Id X-Signature X-Timestamp].each { |name| refute headers.key?(name), name }
    assert_equal({ "productId" => "P", "currency" => "USD" }, requests.first[:body])
  end

  def test_needs_a_slug_and_a_known_environment
    assert_raises(Waffo::Pancake::ConfigurationError) do
      Waffo::Pancake::StoreCheckout.new(store_slug: " ", environment: "test")
    end
    assert_raises(Waffo::Pancake::ConfigurationError) do
      Waffo::Pancake::StoreCheckout.new(store_slug: "s", environment: "live")
    end
  end

  def test_takes_an_idempotency_key
    store, requests = storefront

    store.create_checkout_session(product_id: "P", currency: "USD", idempotency_key: "k")

    assert_equal "k", requests.first[:headers]["X-Idempotency-Key"]
  end
end

class PlanChangeLinkTest < Minitest::Test
  def client_with(environment, checkout_url: "https://x/c")
    requests = []
    answers = [{ token: "tok", expiresAt: "t" }, { sessionId: "cs", checkoutUrl: checkout_url, expiresAt: "e" }]
    transport = lambda do |uri, _headers, json|
      requests << { path: uri.path, body: JSON.parse(json) }
      [200, JSON.generate({ data: answers.shift })]
    end
    [Waffo::Pancake::Client.new(merchant_id: "M", private_key: TestKeys::KEY, environment: environment,
                                transport: transport),
     requests]
  end

  ARGUMENTS = { origin_order_id: "O", product_id: "P", currency: "USD", buyer_identity: "u" }.freeze

  def test_test_links_have_the_flag_before_the_fragment
    client, requests = client_with("test")

    link = client.create_authenticated_plan_change(**ARGUMENTS)

    assert_equal "https://x/c?test=true#token=tok", link["checkoutUrl"]
    assert_equal "tok", link["token"]
    assert_equal({ "buyerIdentity" => "u", "productId" => "P" }, requests[0][:body])
    assert_equal({ "originOrderId" => "O", "productId" => "P", "currency" => "USD" }, requests[1][:body])
  end

  def test_prod_links_have_no_flag
    client, = client_with("prod")

    assert_equal "https://x/c#token=tok", client.create_authenticated_plan_change(**ARGUMENTS)["checkoutUrl"]
  end

  def test_a_url_with_a_query_keeps_it
    client, = client_with("test", checkout_url: "https://x/c?a=1")

    assert_equal "https://x/c?a=1&test=true#token=tok", client.create_authenticated_plan_change(**ARGUMENTS)["checkoutUrl"]
  end

  def test_an_unknown_environment_fails_before_any_token_is_issued
    client, requests = client_with(nil)

    assert_raises(Waffo::Pancake::ConfigurationError) { client.create_authenticated_plan_change(**ARGUMENTS) }
    assert_empty requests
  end
end
