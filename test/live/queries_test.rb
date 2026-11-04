# frozen_string_literal: true

require_relative "live_helper"

# Runs every default selection, so a field the schema does not have fails here. Read-only.
class LiveQueriesTest < LiveAPI::TestCase
  Queries = Waffo::Pancake::API::Queries
  RANGE = { start_date: Time.utc(2026, 1, 1), end_date: Time.utc(2026, 2, 1) }.freeze

  Queries::LISTS.each do |name, spec|
    next if spec[:scope] == :coupon # needs a real coupon; see LiveActionsTest

    define_method(:"test_#{name}_match_the_schema") do
      assert_kind_of Array, client.public_send(name, limit: 1)
      assert_kind_of Integer, client.public_send(:"#{name}_count")
    end
  end

  Queries::AGGREGATES.each_key do |name|
    define_method(:"test_#{name}_matches_the_schema") do
      assert_kind_of Integer, client.public_send(name).fetch("count")
    end
  end

  def test_grouped_aggregate
    assert_kind_of Array, client.payments_aggregate(group_by: :status, granularity: :month).fetch("groups")
  end

  def test_analytics
    assert_kind_of Integer, client.order_statistics(fields: "totalCount", **RANGE).fetch("totalCount")
    assert client.payment_statistics(fields: "successRate { totalAttempts }", **RANGE).key?("successRate")
    assert client.settlement_analysis(fields: "countsByAccountingStatus { status count }", **RANGE)
      .key?("countsByAccountingStatus")
    assert_equal "PayoutAnalysis", client.payout_analysis(fields: "__typename", **RANGE).fetch("__typename")
  end

  def test_store_and_me
    assert_equal ENV.fetch("WAFFO_STORE_ID"), client.store.fetch("id")
    assert_equal ENV.fetch("WAFFO_MERCHANT_ID"), client.me.fetch("id")
  end

  def test_notification_recipients
    assert_kind_of Array, client.notification_recipients(limit: 1)
    assert_kind_of Integer, client.notification_recipients_count
  end

  def test_filter_variable_reaches_an_enum_field
    assert_kind_of Array, client.coupons(filter: { status: { eq: "active" } }, limit: 1)
  end

  def test_webhook_deliveries
    assert_kind_of Array, client.webhook_deliveries(status: :failed, limit: 1)
    assert_kind_of Integer, client.webhook_deliveries_count
  end

  def test_an_unknown_record_is_nil
    assert_nil client.subscription_order(LiveAPI::UNKNOWN_ORDER)
    assert_nil client.payment(LiveAPI::UNKNOWN_PAYMENT)
  end
end
