# frozen_string_literal: true

require "logger"
require "stringio"
require "test_helper"

class RequestsTest < Minitest::Test
  def client_with(*responses, **options)
    requests = []
    transport = lambda do |uri, headers, json|
      requests << { uri: uri, headers: headers, body: json }
      responses.shift
    end
    [Waffo::Pancake::Client.new(merchant_id: "MER_x", private_key: TestKeys::KEY, transport: transport, **options),
     requests]
  end

  def ok(data = {}) = [200, JSON.generate({ data: data })]

  # --- Idempotency ---------------------------------------------------------------------

  def test_no_idempotency_header_is_sent_by_default
    client, requests = client_with(ok)

    client.create_store(name: "S")

    refute requests.first[:headers].key?("X-Idempotency-Key")
  end

  def test_the_longest_idempotency_key_is_accepted
    client, requests = client_with(ok)

    client.create_store(name: "S", idempotency_key: "a" * 256)

    assert_equal 256, requests.first[:headers]["X-Idempotency-Key"].size
  end

  def test_invalid_idempotency_keys_never_reach_waffo
    client, requests = client_with

    ["", "a" * 257, "has space", "a/b", "a\nb", 42].each do |key|
      assert_raises(ArgumentError, key.inspect) { client.create_store(name: "S", idempotency_key: key) }
    end
    assert_empty requests
  end

  def test_issue_session_token_takes_an_idempotency_key
    client, requests = client_with(ok(token: "t"))

    client.issue_session_token(buyer_identity: "u", product_id: "P", idempotency_key: "k")

    assert_equal "k", requests.first[:headers]["X-Idempotency-Key"]
    assert_equal({ "buyerIdentity" => "u", "productId" => "P" }, JSON.parse(requests.first[:body]))
  end

  def test_authenticated_checkout_applies_the_key_to_the_session_only
    client, requests = client_with(ok(token: "t"), ok(checkoutUrl: "https://x/c"))

    client.create_authenticated_checkout(product_id: "P", currency: "USD", buyer_identity: "u", idempotency_key: "k")

    refute requests[0][:headers].key?("X-Idempotency-Key")
    assert_equal "k", requests[1][:headers]["X-Idempotency-Key"]
  end

  def test_action_takes_the_key_and_keyword_params
    client, requests = client_with(ok, ok)

    client.action("/v1/actions/x/y", { a_b: 1 }, idempotency_key: "k")
    client.action("/v1/actions/x/y", a_b: 2)

    assert_equal "k", requests[0][:headers]["X-Idempotency-Key"]
    assert_equal({ "aB" => 1 }, JSON.parse(requests[0][:body]))
    assert_equal({ "aB" => 2 }, JSON.parse(requests[1][:body]))
  end

  # --- Explicit null -------------------------------------------------------------------

  def test_null_sends_json_null_and_nil_is_dropped
    client, requests = client_with(ok)

    client.update_webhook(id: "W", secret: Waffo::Pancake::NULL, url: nil)

    assert_equal '{"id":"W","secret":null}', requests.first[:body]
  end

  def test_null_also_serializes_inside_a_nested_hash
    assert_equal '{"a":null}', JSON.generate({ a: Waffo::Pancake::NULL })
  end

  # --- Retry-After ---------------------------------------------------------------------

  def test_retry_after_seconds_are_read_from_a_429
    client, = client_with([429, '{"errors":[{"message":"slow"}]}', { "Retry-After" => "30" }])

    error = assert_raises(Waffo::Pancake::Unavailable) { client.create_store(name: "S") }

    assert_equal 30, error.retry_after
  end

  def test_retry_after_header_lookup_ignores_case_and_takes_net_http_arrays
    client, = client_with([429, "{}", { "retry-after" => ["7"] }])

    assert_equal 7, assert_raises(Waffo::Pancake::Unavailable) { client.create_store(name: "S") }.retry_after
  end

  def test_retry_after_http_date_becomes_seconds_and_never_goes_negative
    future = (Time.now + 120).httpdate
    client, = client_with([503, "{}", { "Retry-After" => future }],
                          [503, "{}", { "Retry-After" => "Wed, 21 Oct 2015 07:28:00 GMT" }])

    assert_in_delta 120, assert_raises(Waffo::Pancake::Unavailable) { client.create_store(name: "S") }.retry_after, 5
    assert_equal 0, assert_raises(Waffo::Pancake::Unavailable) { client.create_store(name: "S") }.retry_after
  end

  def test_retry_after_is_nil_when_missing_or_unusable
    client, = client_with([429, "{}"], [429, "{}", { "Retry-After" => "soon" }], [400, "{}", {}])

    assert_nil assert_raises(Waffo::Pancake::Unavailable) { client.create_store(name: "S") }.retry_after
    assert_nil assert_raises(Waffo::Pancake::Unavailable) { client.create_store(name: "S") }.retry_after
    assert_nil assert_raises(Waffo::Pancake::Rejected) { client.create_store(name: "S") }.retry_after
  end

  def test_graphql_failures_carry_retry_after_too
    client, = client_with([429, '{"errors":[{"message":"slow"}]}', { "Retry-After" => "5" }])

    assert_equal 5, assert_raises(Waffo::Pancake::Unavailable) { client.graphql("{ me { id } }") }.retry_after
  end

  # --- Warnings and failures -----------------------------------------------------------

  def test_warnings_join_the_result
    client, = client_with([200, JSON.generate({ data: { store: { id: "S" } }, warnings: [{ message: "ignored" }] })])

    assert_equal({ "store" => { "id" => "S" }, "warnings" => [{ "message" => "ignored" }] },
                 client.update_store(id: "S"))
  end

  def test_warnings_are_logged_as_a_count_and_not_their_text
    log = StringIO.new
    client, = client_with([200, JSON.generate({ data: {}, warnings: [{ message: "private text" }] })],
                          logger: Logger.new(log))

    client.update_store(id: "S")

    assert_includes log.string, "warnings=1"
    refute_includes log.string, "private text"
  end

  def test_logs_hold_no_body_or_credentials
    log = StringIO.new
    client, = client_with(ok, logger: Logger.new(log))

    client.create_store(name: "secret store", idempotency_key: "secret_key")

    refute_includes log.string, "secret"
  end

  def test_graphql_raises_on_a_failed_status_without_errors
    client, = client_with([500, "{}"], [403, '{"data":null}'])

    assert_raises(Waffo::Pancake::Unavailable) { client.graphql("{ me { id } }") }
    assert_raises(Waffo::Pancake::Rejected) { client.graphql("{ me { id } }") }
  end

  def test_graphql_keeps_partial_data
    client, = client_with([200, JSON.generate({ data: { me: { id: "M" } }, errors: [{ message: "part" }] })])

    assert_equal({ "me" => { "id" => "M" } }, client.graphql("{ me { id } }"))
  end

  def test_non_json_success_is_rejected
    client, = client_with([200, "<html>"])

    assert_raises(Waffo::Pancake::Rejected) { client.create_store(name: "S") }
  end

  def test_two_part_and_three_part_transport_answers_both_work
    client, = client_with(ok(a: 1), [200, '{"data":{"a":2}}', {}])

    assert_equal 1, client.create_store(name: "S")["a"]
    assert_equal 2, client.create_store(name: "S")["a"]
  end

  def test_instrumenter_sees_the_status_and_no_body
    events = []
    instrumenter = Object.new
    instrumenter.define_singleton_method(:instrument) do |name, payload, &block|
      block.call(payload).tap { events << [name, payload] }
    end
    client, = client_with(ok, instrumenter: instrumenter)

    client.create_store(name: "S")

    assert_equal [["request.waffo_pancake",
                   { method: "POST", path: "/v1/actions/store/create-store", status: 200 }]], events
  end

  def test_network_error_alias_is_kept_for_callers
    assert_same Waffo::Pancake::Connection::NETWORK_ERRORS, Waffo::Pancake::Client::NETWORK_ERRORS
  end

  # --- Environment ---------------------------------------------------------------------

  def test_client_rejects_an_unknown_environment
    assert_raises(Waffo::Pancake::ConfigurationError) do
      Waffo::Pancake::Client.new(merchant_id: "M", private_key: TestKeys::KEY, environment: "staging")
    end
  end

  def test_client_inspect_hides_the_key
    client, = client_with

    refute_match(/PRIVATE|private_key|PKey/, client.inspect)
  end
end
