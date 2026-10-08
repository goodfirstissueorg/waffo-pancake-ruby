# frozen_string_literal: true

require_relative "rails_helper"

class WebhookControllerTest < Minitest::Test
  include Waffo::Pancake::TestHelpers

  def deliver(event, headers: nil)
    body = event.is_a?(String) ? event : JSON.generate(event)
    env = (headers || waffo_webhook_headers(body)).transform_keys { |key| key == "CONTENT_TYPE" ? key : "HTTP_#{key.upcase.tr("-", "_")}" }
    with_waffo_webhook_key { Rack::MockRequest.new(Rails.application).post("/webhooks/waffo", input: body, **env) }
  end

  def test_a_signed_delivery_reaches_the_action_without_its_body_in_params
    response = deliver(waffo_webhook_event("subscription.activated", id: "evt_1", data: { orderId: "ORD_1" }))

    assert_equal 200, response.status
    body = JSON.parse(response.body)
    assert_equal "evt_1", body["id"]
    assert_equal "subscription.activated", body["type"]
    refute_includes body["params"], "data", "the payload is not parsed into params"
  end

  def test_a_bad_signature_is_refused_before_the_action
    event = JSON.generate(waffo_webhook_event("subscription.activated"))
    response = deliver(event, headers: waffo_webhook_headers("{}"))

    assert_equal 401, response.status
  end

  def test_another_environment_or_store_is_acknowledged_and_skipped
    other_mode = deliver(waffo_webhook_event("subscription.activated", mode: "prod"))
    other_store = deliver(waffo_webhook_event("subscription.activated", store_id: "STO_someone_else"))

    assert_equal [200, 200], [other_mode.status, other_store.status]
    assert_empty other_mode.body
    assert_empty other_store.body
  end

  def test_an_oversized_body_is_refused
    response = deliver("x" * (Waffo::Pancake::WebhookController::MAX_BODY_BYTES + 1))

    assert_equal 413, response.status
  end

  def test_verification_is_reported_with_its_outcome
    events = []
    subscriber = ActiveSupport::Notifications.subscribe("verify_webhook.waffo_pancake") { |event| events << event.payload }

    deliver(waffo_webhook_event("refund.succeeded", id: "evt_9"))
    deliver(JSON.generate(waffo_webhook_event("refund.succeeded")), headers: waffo_webhook_headers("{}"))

    assert_equal "evt_9", events.first[:event_id]
    assert_equal "Waffo::Pancake::InvalidSignature", events.last[:exception].first
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end
end
