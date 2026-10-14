# frozen_string_literal: true

require "test_helper"

class WebhookEventTest < Minitest::Test
  # Records what it is told instead of printing it.
  class Recorder
    attr_reader :messages

    def initialize = @messages = []
    def warn(message, _callstack = nil) = messages << message
  end

  PAYMENT = {
    "id" => "dlv_1", "eventType" => "subscription.payment_succeeded", "eventId" => "PAY_1", "storeId" => "STO_1",
    "mode" => "test",
    "data" => {
      "orderId" => "ORD_1", "currency" => "USD", "amount" => "4.50", "total" => "9.00", "taxAmount" => "0",
      "chargedAmount" => "4.50", "periodNumber" => 1,
      "listPrice" => { "total" => "9.00", "subtotal" => "9.00", "taxAmount" => "0", "taxRate" => 0 }
    }
  }.freeze

  def setup
    @recorder = Recorder.new
    Waffo::Pancake.configuration.deprecator = @recorder
  end

  def teardown = Waffo::Pancake.reset!

  def event(payload = PAYMENT) = Waffo::Pancake::Webhook::Event.wrap(payload)

  def test_verify_returns_an_event
    body = JSON.generate(PAYMENT)
    verified = Waffo::Pancake::Webhook.verify(body, TestKeys.webhook_header(body), public_key: TestKeys::KEY.public_key)

    assert_kind_of Waffo::Pancake::Webhook::Event, verified
    assert_kind_of Hash, verified, "still a Hash for code written against 0.2"
    assert_equal PAYMENT, verified
    assert_equal "4.50", verified.data.charged_amount
  end

  def test_envelope_readers
    event = event()

    assert_equal %w[dlv_1 subscription.payment_succeeded PAY_1 STO_1], [event.id, event.event_type, event.event_id,
                                                                       event.store_id]
    assert event.test?
    assert event.payment?
    refute event.refund?
    refute event.subscription?
    assert_equal :subscription, Waffo::Pancake::Webhook.family("subscription.renewed")
    assert_equal :refund, Waffo::Pancake::Webhook.family("refund.failed")
    assert_nil Waffo::Pancake::Webhook.family("store.created")
  end

  def test_new_amount_fields_read_without_warnings
    data = event.data

    assert_equal "4.50", data.charged_amount
    assert_equal "9.00", data.list_price["total"]
    assert_equal data.list_price, data.price
    assert_equal 1, data.period_number
    assert data.first_period?
    refute data.renewal?
    assert_equal "ORD_1", data["orderId"]
    assert_empty @recorder.messages
  end

  def test_reading_a_deprecated_field_answers_it_and_names_the_replacement_for_the_family
    data = event.data

    assert_equal "4.50", data["amount"]
    assert_equal "9.00", data.fetch("total")
    assert_equal "0", data.dig("taxAmount")

    assert_equal 3, @recorder.messages.size
    assert_match(/data\["amount"\] is deprecated on subscription\.payment_succeeded; read data\["chargedAmount"\]/,
                 @recorder.messages[0])
    assert_match(/read data\.dig\("listPrice", "total"\)/, @recorder.messages[1])
    assert_match(/not before 2027-09-20/, @recorder.messages[2])
  end

  def test_replacements_differ_per_family
    refund = event(PAYMENT.merge("eventType" => "refund.succeeded"))
    renewal = event(PAYMENT.merge("eventType" => "subscription.renewed"))
    unknown = event(PAYMENT.merge("eventType" => nil))

    refund.data["amount"]
    renewal.data["amount"]
    unknown.data["subtotal"]

    assert_match(/read data\["refundedAmount"\]/, @recorder.messages[0])
    assert_match(/read data\.dig\("planPrice", "total"\)/, @recorder.messages[1])
    assert_match(/data\.dig\("listPrice", "subtotal"\) on payment events, .*originalPayment.* on refund events/,
                 @recorder.messages[2])
  end

  def test_nested_dig_from_the_event_warns_too
    event.dig("data", "taxRate")

    assert_equal 1, @recorder.messages.size
  end

  def test_iterating_and_serializing_do_not_warn
    event = event()
    JSON.generate(event)
    event.data.each { |_key, _value| nil }
    event.data.key?("amount")

    assert_empty @recorder.messages
  end

  def test_wrap_takes_json_and_symbol_keys_and_keeps_an_event_as_is
    from_json = event(JSON.generate(PAYMENT))
    from_symbols = event({ id: "dlv_2", eventType: "refund.succeeded", data: { refundedAmount: "1.00" } })

    assert_equal "4.50", from_json.data.charged_amount
    assert_equal "1.00", from_symbols.data.refunded_amount
    assert_same from_json, Waffo::Pancake::Webhook::Event.wrap(from_json)
    assert_raises(ArgumentError) { Waffo::Pancake::Webhook::Event.wrap([1]) }
  end

  def test_an_event_without_data_has_empty_data
    assert_empty event({ "id" => "dlv_3", "eventType" => "order.completed" }).data
  end

  def test_renewal_and_unknown_periods
    renewal = event(PAYMENT.merge("data" => { "periodNumber" => 3 })).data
    one_time = event(PAYMENT.merge("data" => {})).data

    assert renewal.renewal?
    refute renewal.first_period?
    refute one_time.renewal?
    refute one_time.first_period?
  end

  def test_nil_deprecator_is_silent
    Waffo::Pancake.configuration.deprecator = nil

    assert_equal "4.50", event.data["amount"]
  end

  def test_the_default_warner_prints_each_message_once
    Waffo::Pancake.reset!
    warner = Waffo::Pancake::Deprecation::Warner.new
    Waffo::Pancake.configuration.deprecator = warner

    _, err = capture_io do
      2.times { event.data["amount"] }
    end

    assert_equal 1, err.scan("DEPRECATION WARNING").size
    assert_match(/called from .*webhook_event_test\.rb/, err)
    assert_same Waffo::Pancake::Deprecation.default, Waffo::Pancake::Configuration.new.deprecator
  end
end
