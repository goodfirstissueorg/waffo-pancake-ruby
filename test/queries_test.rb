# frozen_string_literal: true

require "test_helper"

class QueriesTest < Minitest::Test
  Queries = Waffo::Pancake::API::Queries

  def client_with(answer: {}, store_id: "STO_1")
    requests = []
    transport = lambda do |_uri, _headers, json|
      requests << JSON.parse(json)
      [200, JSON.generate({ data: answer })]
    end
    [Waffo::Pancake::Client.new(merchant_id: "M", private_key: TestKeys::KEY, store_id: store_id, transport: transport),
     requests]
  end

  def owner_for(spec) = spec[:scope] == :coupon ? { coupon_id: "COU_1" } : {}

  Queries::LISTS.each do |name, spec|
    define_method(:"test_#{name}_list_and_count_read_their_field") do
      client, requests = client_with(answer: { spec[:field] => [{ "id" => "x" }], "#{spec[:field]}Count" => 3 })

      assert_equal [{ "id" => "x" }], client.public_send(name, limit: 5, offset: 10, **owner_for(spec))
      assert_equal 3, client.public_send(:"#{name}_count", **owner_for(spec))

      list = requests[0]
      assert_includes list["query"], "#{spec[:field]}("
      assert_includes list["query"], "$limit: Int"
      assert_equal 5, list["variables"]["limit"]
      assert_equal 10, list["variables"]["offset"]
      assert_includes requests[1]["query"], "#{spec[:field]}Count"
      refute_includes requests[1]["query"], "$limit"
    end

    define_method(:"test_#{name}_filter_travels_as_a_typed_variable") do
      client, requests = client_with(answer: { spec[:field] => [] })
      hostile = 'x" } }) { secret } #'

      client.public_send(name, filter: { id: { eq: hostile } }, **owner_for(spec))

      assert_includes requests[0]["query"], "$filter: #{spec[:type]}Filter"
      refute_includes requests[0]["query"], hostile
      assert_equal({ "id" => { "eq" => hostile } }, requests[0]["variables"]["filter"])
    end

    next unless spec[:single]

    define_method(:"test_#{spec[:single]}_reads_one_by_id") do
      field = spec[:single].to_s.gsub(/_([a-z])/) { Regexp.last_match(1).upcase }
      client, requests = client_with(answer: { field => { "id" => "x" } })

      assert_equal({ "id" => "x" }, client.public_send(spec[:single], "x"))
      assert_includes requests[0]["query"], "#{field}(id: $id)"
      assert_equal({ "id" => "x" }, requests[0]["variables"])
    end
  end

  def test_required_store_defaults_to_the_configured_one
    client, requests = client_with(answer: { "coupons" => [] })

    client.coupons

    assert_includes requests[0]["query"], "$storeId: String!"
    assert_equal "STO_1", requests[0]["variables"]["storeId"]
  end

  def test_required_store_is_checked_before_calling_waffo
    client, requests = client_with(store_id: nil)

    assert_raises(ArgumentError) { client.coupons }
    assert_raises(ArgumentError) { client.customers_count }
    assert_raises(ArgumentError) { client.notification_recipients }
    assert_empty requests
  end

  def test_a_slug_replaces_the_configured_store
    client, requests = client_with(answer: { "onetimeProducts" => [] })

    client.onetime_products(store_slug: "my-store")

    assert_equal({ "storeSlug" => "my-store" }, requests[0]["variables"])
  end

  def test_an_owner_a_query_cannot_take_is_refused_rather_than_dropped
    client, requests = client_with

    assert_raises(ArgumentError) { client.refunds(store_id: "STO_2") }
    assert_raises(ArgumentError) { client.coupons(store_slug: "s") }
    assert_raises(ArgumentError) { client.payments_count(coupon_id: "c") }
    assert_empty requests
  end

  def test_promotion_codes_need_a_coupon
    client, requests = client_with

    assert_raises(ArgumentError) { client.promotion_codes }
    assert_empty requests
  end

  def test_order_by_is_typed_and_refused_where_the_schema_has_none
    client, requests = client_with(answer: { "payments" => [] })

    client.payments(order_by: :created_at_desc)

    assert_includes requests[0]["query"], "$orderBy: [PaymentOrderBy!]"
    assert_equal ["created_at_desc"], requests[0]["variables"]["orderBy"]
    assert_raises(ArgumentError) { client.coupons(order_by: "created_at_desc") }
  end

  def test_limit_must_be_a_number
    client, = client_with

    assert_raises(ArgumentError) { client.payments(limit: "ten") }
  end

  def test_fields_can_be_replaced
    client, requests = client_with(answer: { "stores" => [] })

    client.stores(fields: "id name")

    assert_includes requests[0]["query"], "{ id name }"
  end

  def test_no_argument_queries_have_no_parentheses
    client, requests = client_with(answer: { "stores" => [] })

    client.stores

    assert_match(/\Aquery \{ stores \{/, requests[0]["query"])
    assert_equal({}, requests[0]["variables"])
  end

  def test_a_nil_answer_is_an_empty_list
    client, = client_with(answer: { "stores" => nil })

    assert_equal [], client.stores
  end

  def test_store_defaults_to_the_configured_one_or_takes_a_slug
    client, requests = client_with(answer: { "store" => { "id" => "STO_1" } })

    assert_equal "STO_1", client.store["id"]
    assert_equal({ "id" => "STO_1" }, requests[0]["variables"])
    client.store(slug: "s")
    assert_equal({ "slug" => "s" }, requests[1]["variables"])
    client.store("STO_2")
    assert_equal({ "id" => "STO_2" }, requests[2]["variables"])
  end

  def test_store_needs_some_identifier
    client, = client_with(store_id: nil)

    assert_raises(ArgumentError) { client.store }
  end

  def test_me_and_versions_and_recipients
    client, requests = client_with(answer: { "me" => { "id" => "M" }, "onetimeProductVersions" => [],
                                             "subscriptionProductVersions" => [], "storeNotificationRecipients" => [],
                                             "storeNotificationRecipientsCount" => 2 })

    assert_equal "M", client.me["id"]
    assert_equal [], client.onetime_product_versions("P")
    assert_equal [], client.subscription_product_versions("P")
    assert_equal [], client.notification_recipients(limit: 1)
    assert_equal 2, client.notification_recipients_count
    assert_equal({ "productId" => "P" }, requests[1]["variables"])
    assert_includes requests[3]["query"], "notifyRefundSucceeded"
  end

  Queries::ANALYTICS.each do |name, field|
    define_method(:"test_#{name}_sends_the_filter_and_requires_fields") do
      client, requests = client_with(answer: { field => { "totalCount" => 1 } })

      result = client.public_send(name, fields: "totalCount", start_date: Time.utc(2026, 1, 1),
                                        end_date: "2026-02-01T00:00:00Z", currency: "USD", status: "paid")

      assert_equal({ "totalCount" => 1 }, result)
      assert_includes requests[0]["query"], "$filter: AnalyticsFilterInput!"
      assert_equal({ "storeId" => "STO_1",
                     "filter" => { "timeRange" => { "startDate" => "2026-01-01T00:00:00Z",
                                                    "endDate" => "2026-02-01T00:00:00Z" },
                                   "currency" => "USD", "status" => "paid" } }, requests[0]["variables"])
      assert_raises(ArgumentError) { client.public_send(name, start_date: "a", end_date: "b") }
    end
  end

  def test_analytics_need_a_store
    client, requests = client_with(store_id: nil)

    assert_raises(ArgumentError) { client.order_statistics(fields: "totalCount", start_date: "a", end_date: "b") }
    assert_empty requests
  end

  def test_analytics_do_not_change_the_given_time
    client, = client_with(answer: { "orderStatistics" => {} })
    time = Time.new(2026, 1, 1, 8, 0, 0, "+08:00")

    client.order_statistics(fields: "totalCount", start_date: time, end_date: time)

    assert_equal 8 * 3600, time.utc_offset
  end

  def test_payout_analysis_takes_a_merchant
    client, requests = client_with(answer: { "payoutAnalysis" => {} })

    client.payout_analysis(fields: "x", start_date: "a", end_date: "b", merchant_id: "M")

    assert_equal "M", requests[0]["variables"]["merchantId"]
    refute requests[0]["variables"].key?("storeId")
  end

  Queries::AGGREGATES.each do |name, (field, type, has_amount)|
    define_method(:"test_#{name}_sends_grouping_and_selects_only_what_it_reports") do
      client, requests = client_with(answer: { field => { "count" => 1 } })

      assert_equal 1, client.public_send(name, filter: { x: 1 }, group_by: :status, granularity: :month)["count"]

      assert_includes requests[0]["query"], "$groupBy: [#{type}Dimension!]"
      assert_equal(has_amount, requests[0]["query"].include?("amount {"))
      assert_equal({ "filter" => { "x" => 1 }, "groupBy" => ["status"], "granularity" => "month" },
                   requests[0]["variables"])
    end
  end
end
