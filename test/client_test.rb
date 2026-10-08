# frozen_string_literal: true

require "test_helper"

class ClientTest < Minitest::Test
  def client_with(*responses)
    requests = []
    transport = lambda do |uri, headers, json|
      requests << { uri: uri, headers: headers, body: json }
      responses.shift
    end
    [Waffo::Pancake::Client.new(merchant_id: "MER_x", private_key: TestKeys::KEY.private_to_pem, transport: transport),
     requests]
  end

  def ok(data) = [200, JSON.generate({ data: data })]

  def test_signs_method_path_timestamp_and_body_hash
    client, requests = client_with(ok(orderId: "ORD_1", status: "canceling"))

    assert_equal({ "orderId" => "ORD_1", "status" => "canceling" }, client.cancel_subscription("ORD_1"))

    request = requests.first
    assert_equal "https://api.waffo.ai/v1/actions/subscription-order/cancel-order", request[:uri].to_s
    assert_equal "MER_x", request[:headers]["X-Merchant-Id"]
    assert_equal({ "orderId" => "ORD_1" }, JSON.parse(request[:body]))

    body_hash = Base64.strict_encode64(OpenSSL::Digest::SHA256.digest(request[:body]))
    canonical = "POST\n/v1/actions/subscription-order/cancel-order\n#{request[:headers]["X-Timestamp"]}\n#{body_hash}"
    signature = Base64.strict_decode64(request[:headers]["X-Signature"])
    assert TestKeys::KEY.public_key.verify(OpenSSL::Digest::SHA256.new, signature, canonical)
  end

  def test_camelizes_top_level_keys_only_and_drops_nils
    client, requests = client_with(ok(sessionId: "cs", checkoutUrl: "u", expiresAt: "e"))

    client.create_checkout_session(product_id: "PROD_1", currency: "USD", buyer_email: "a@example.com",
                                   success_url: nil, metadata: { "user_id" => "7" })

    assert_equal({ "productId" => "PROD_1", "currency" => "USD", "buyerEmail" => "a@example.com",
                   "metadata" => { "user_id" => "7" } }, JSON.parse(requests.first[:body]))
  end

  def test_authenticated_checkout_appends_the_token_fragment
    client, requests = client_with(
      ok(token: "tok", expiresAt: "t"),
      ok(sessionId: "cs_1", checkoutUrl: "https://pancake.waffo.ai/store/s/checkout/cs_1", expiresAt: "e")
    )

    result = client.create_authenticated_checkout(product_id: "PROD_1", currency: "USD", buyer_identity: "user-1")

    assert_equal "https://pancake.waffo.ai/store/s/checkout/cs_1#token=tok", result["checkoutUrl"]
    assert_equal({ "buyerIdentity" => "user-1", "productId" => "PROD_1" }, JSON.parse(requests[0][:body]))
    assert_equal "/v1/actions/checkout/create-session", requests[1][:uri].path
  end

  def test_refusals_are_rejected_and_outages_unavailable
    client, = client_with(
      [400, JSON.generate({ data: nil, errors: [{ message: "Order is not active", layer: "order" }] })],
      [503, "<html>down</html>"],
      [429, JSON.generate({ errors: [{ message: "slow down" }] })]
    )

    error = assert_raises(Waffo::Pancake::Rejected) { client.cancel_subscription("ORD_1") }
    assert_equal 400, error.status
    assert_match(/Order is not active/, error.message)
    assert_raises(Waffo::Pancake::Unavailable) { client.cancel_subscription("ORD_1") }
    assert_raises(Waffo::Pancake::Unavailable) { client.cancel_subscription("ORD_1") }
  end

  def test_network_errors_are_unavailable
    transport = ->(*) { raise Errno::ECONNREFUSED }
    client = Waffo::Pancake::Client.new(merchant_id: "MER_x", private_key: TestKeys::KEY, transport: transport)

    assert_raises(Waffo::Pancake::Unavailable) { client.reactivate_subscription("ORD_1") }
  end

  def test_subscription_order_reads_graphql_and_is_nil_when_unknown
    client, requests = client_with(
      ok(subscriptionOrder: { id: "ORD_1", status: "active", subscriptionProduct: { id: "PROD_1" } }),
      ok(subscriptionOrder: nil)
    )

    order = client.subscription_order("ORD_1")
    assert_equal "active", order["status"]
    assert_equal "PROD_1", order["productId"]
    assert_match(/subscriptionProduct \{ id \}/, JSON.parse(requests.first[:body])["query"])
    assert_nil client.subscription_order("ORD_2")
    assert_equal({ "id" => "ORD_1" }, JSON.parse(requests.first[:body])["variables"])
  end

  def test_graphql_errors_without_data_raise
    client, = client_with([200, JSON.generate({ data: nil, errors: [{ message: "Unknown type" }] })])

    assert_raises(Waffo::Pancake::Rejected) { client.graphql("{ x }") }
  end

  def test_requires_merchant_id_and_a_valid_key
    assert_raises(Waffo::Pancake::ConfigurationError) { Waffo::Pancake::Client.new(merchant_id: nil, private_key: "x") }
    assert_raises(Waffo::Pancake::ConfigurationError) { Waffo::Pancake::Client.new(merchant_id: "M", private_key: "nope") }
  end
end
