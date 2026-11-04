# frozen_string_literal: true

require "time"

module Waffo
  module Pancake
    module API
      # GraphQL reads, generated from the tables below. The tables follow the schema that
      # introspection reports, not the documentation pages: those show a `version` field on
      # products, `prices` as a scalar and `filter` on the version queries, and none of those exist.
      # test/live/queries_test.rb runs every default selection against the real schema.
      #
      # Filters travel as GraphQL variables, so user data is never interpolated into a query.
      # `fields:` is interpolated: it must come from your code, never from a request.
      module Queries
        PRICES = "prices { currency priceInfo { amount taxCategory } }"
        SUBSCRIPTION_PRICES = "prices { currency priceInfo { amount taxCategory trialAmount } }"
        MEDIA = "media { type url alt thumbnail }"
        AGGREGATE_METRICS = "amount { sum avg min max }"

        STORE_FIELDS = "id name status slug logo supportEmail website prodEnabled createdAt updatedAt"
        ONETIME_PRODUCT_FIELDS = "id storeId name description #{PRICES} status #{MEDIA} successUrl metadata " \
                                 "createdAt updatedAt"
        SUBSCRIPTION_PRODUCT_FIELDS = "id storeId name description billingPeriod #{SUBSCRIPTION_PRICES} status " \
                                      "#{MEDIA} successUrl metadata createdAt updatedAt"
        GROUP_FIELDS = "id storeId name description rules { sharedTrial selfServicePlanChange } productIds " \
                       "environment createdAt updatedAt"
        ORDER_FIELDS = "id storeId status testMode buyerEmail merchantProvidedBuyerIdentity orderMerchantExternalId " \
                       "currency metadata createdAt updatedAt"
        SUBSCRIPTION_ORDER_FIELDS = "#{ORDER_FIELDS} billingPeriod isInTrial willRenew canReactivate " \
                                    "currentPeriodStart currentPeriodEnd canceledAt"
        PAYMENT_FIELDS = "id orderId status refundStatus orderMerchantExternalId periodNumber testMode " \
                         "snapshotAmountDetails { subtotal listTotal discountAmount taxAmount total currency } createdAt"
        REFUND_FIELDS = "id paymentId ticketId status testMode orderMerchantExternalId " \
                        "refundTicketMerchantExternalId pspAmountDetails { amount currency } createdAt"
        REFUND_TICKET_FIELDS = "id status refundTicketMerchantExternalId " \
                               "versionData { reason requestedAmount { amount currency } } reviewNote rejectReason " \
                               "executedAt createdAt updatedAt"
        CHARGEBACK_FIELDS = "id paymentId orderId storeId status reason reasonCode amount { amount currency } " \
                            "testMode createdAt updatedAt"
        CUSTOMER_FIELDS = "id email name country status testMode orderCount subscriptionCount " \
                          "activeSubscriptionCount createdAt updatedAt"
        COUPON_FIELDS = "id storeId name code status redeemable discountType percentOff amountOff { amount currency } " \
                        "duration durationInPeriods productIds maxRedemptions redeemBy timesRedeemed " \
                        "promotionCodesCount createdAt updatedAt"
        PROMOTION_CODE_FIELDS = "id couponId code status batchId timesRedeemed createdAt"
        DISCOUNT_APPLICATION_FIELDS = "id orderId couponId promotionCodeId code sourceType entryChannel appliedVia " \
                                      "status listAmount { amount currency } discountAmount { amount currency } createdAt"
        EMAIL_DELIVERY_FIELDS = "id storeId eventType eventId recipientType toAddress subject testMode status " \
                                "sentAt deliveredAt bounceType errorMessage createdAt"
        CANCEL_REASON_FIELDS = "id orderId storeId reasonCode reasonDetail createdAt"
        MERCHANT_FIELDS = "id email name status createdAt updatedAt"
        STORE_MERCHANT_FIELDS = "id storeId merchantId role memberEmail memberName createdAt updatedAt"
        WEBHOOK_FIELDS = "id storeId channel url events testMode secret createdAt updatedAt"
        RECIPIENT_FIELDS = "id storeId email isPrimary createdAt preferences { notifyNewOrders notifyNewSubscriptions " \
                           "notifySubscriptionCanceled notifySubscriptionRenewed notifySubscriptionEnded " \
                           "notifySubscriptionPastDue notifySubscriptionUncanceled notifySubscriptionPlanChanged " \
                           "notifyChargeback notifyRefundSucceeded }"
        ONETIME_VERSION_FIELDS = "id productId versionNumber name description #{PRICES} #{MEDIA} successUrl metadata " \
                                 "createdAt isTestVersion isProdVersion"
        SUBSCRIPTION_VERSION_FIELDS = "id productId versionNumber name description billingPeriod " \
                                      "#{SUBSCRIPTION_PRICES} #{MEDIA} successUrl metadata createdAt isTestVersion " \
                                      "isProdVersion"

        # scope: how the list is tied to its owner.
        #   :store      storeId: String! (defaults to the configured store)
        #   :store_slug storeId or storeSlug, both optional
        #   :store_opt  storeId: String, optional
        #   :coupon     couponId: String!
        #   nil         no owner argument
        LISTS = {
          stores: { field: "stores", type: "Store", order: true, fields: STORE_FIELDS },
          merchants: { field: "merchants", type: "Merchant", order: true, single: :merchant, fields: MERCHANT_FIELDS },
          store_merchants: { field: "storeMerchants", type: "StoreMerchant", single: :store_merchant,
                             fields: STORE_MERCHANT_FIELDS },
          onetime_products: { field: "onetimeProducts", type: "OnetimeProduct", scope: :store_slug,
                              single: :onetime_product, fields: ONETIME_PRODUCT_FIELDS },
          subscription_products: { field: "subscriptionProducts", type: "SubscriptionProduct", scope: :store_slug,
                                   single: :subscription_product, fields: SUBSCRIPTION_PRODUCT_FIELDS },
          subscription_product_groups: { field: "subscriptionProductGroups", type: "SubscriptionProductGroup",
                                         scope: :store_slug, single: :subscription_product_group, fields: GROUP_FIELDS },
          onetime_orders: { field: "onetimeOrders", type: "OnetimeOrder", scope: :store_slug, order: true,
                            single: :onetime_order, fields: ORDER_FIELDS },
          subscription_orders: { field: "subscriptionOrders", type: "SubscriptionOrder", scope: :store_slug, order: true,
                                 fields: SUBSCRIPTION_ORDER_FIELDS },
          payments: { field: "payments", type: "Payment", scope: :store_opt, order: true, single: :payment,
                      fields: PAYMENT_FIELDS },
          refunds: { field: "refunds", type: "Refund", order: true, single: :refund, fields: REFUND_FIELDS },
          refund_tickets: { field: "refundTickets", type: "RefundTicket", order: true, single: :refund_ticket,
                            fields: REFUND_TICKET_FIELDS },
          chargebacks: { field: "chargebacks", type: "Chargeback", order: true, single: :chargeback,
                         fields: CHARGEBACK_FIELDS },
          customers: { field: "customers", type: "Customer", scope: :store, order: true, fields: CUSTOMER_FIELDS },
          coupons: { field: "coupons", type: "Coupon", scope: :store, single: :coupon, fields: COUPON_FIELDS },
          promotion_codes: { field: "promotionCodes", type: "PromotionCode", scope: :coupon,
                             fields: PROMOTION_CODE_FIELDS },
          discount_applications: { field: "discountApplications", type: "DiscountApplication", scope: :store,
                                   fields: DISCOUNT_APPLICATION_FIELDS },
          email_deliveries: { field: "emailDeliveries", type: "EmailDelivery", scope: :store, order: true,
                              fields: EMAIL_DELIVERY_FIELDS },
          subscription_cancel_reasons: { field: "subscriptionCancelReasons", type: "SubscriptionCancelReason",
                                         scope: :store, order: true, fields: CANCEL_REASON_FIELDS },
          store_webhooks: { field: "storeWebhooks", type: "StoreWebhook", scope: :store, fields: WEBHOOK_FIELDS }
        }.freeze

        # method => [GraphQL field, type prefix, reports an amount]. Delivery and reason aggregates only count.
        AGGREGATES = {
          payments_aggregate: ["paymentsAggregate", "Payment", true],
          refunds_aggregate: ["refundsAggregate", "Refund", true],
          onetime_orders_aggregate: ["onetimeOrdersAggregate", "OnetimeOrder", true],
          subscription_orders_aggregate: ["subscriptionOrdersAggregate", "SubscriptionOrder", true],
          payout_tickets_aggregate: ["payoutTicketsAggregate", "PayoutTicket", true],
          settlement_batches_aggregate: ["settlementBatchesAggregate", "SettlementBatch", true],
          webhook_deliveries_aggregate: ["webhookDeliveriesAggregate", "WebhookDelivery", false],
          email_deliveries_aggregate: ["emailDeliveriesAggregate", "EmailDelivery", false],
          subscription_cancel_reasons_aggregate: ["subscriptionCancelReasonsAggregate", "SubscriptionCancelReason", false]
        }.freeze

        ANALYTICS = {
          order_statistics: "orderStatistics",
          payment_statistics: "paymentStatistics",
          product_statistics: "productStatistics",
          trend_analysis: "trendAnalysis",
          distribution_analysis: "distributionAnalysis",
          customer_analysis: "customerAnalysis",
          tax_analysis: "taxAnalysis",
          subscription_analysis: "subscriptionAnalysis",
          refund_ticket_analysis: "refundTicketAnalysis",
          settlement_analysis: "settlementAnalysis",
          delivery_analysis: "deliveryAnalysis"
        }.freeze

        OWNER_KEYS = { store: [:store_id], store_slug: %i[store_id store_slug], store_opt: [:store_id],
                       coupon: [:coupon_id], nil => [] }.freeze

        # What a stand-in such as TestHelpers::FakeClient should answer, by method name.
        def self.empty_answers
          @empty_answers ||= begin
            answers = {}
            LISTS.each do |name, spec|
              answers[name] = []
              answers[:"#{name}_count"] = 0
              answers[spec[:single]] = nil if spec[:single]
            end
            answers[:onetime_product_versions] = []
            answers[:subscription_product_versions] = []
            answers[:notification_recipients] = []
            answers[:notification_recipients_count] = 0
            answers[:store] = answers[:me] = answers[:payout_analysis] = nil
            AGGREGATES.each_key { |name| answers[name] = nil }
            ANALYTICS.each_key { |name| answers[name] = nil }
            answers.freeze
          end
        end

        LISTS.each do |name, spec|
          define_method(name) do |filter: nil, order_by: nil, limit: nil, offset: nil, fields: spec[:fields], **owner|
            arguments = owner_arguments(spec[:scope], owner, name)
            arguments[:limit] = ["Int", limit && Integer(limit)]
            arguments[:offset] = ["Int", offset && Integer(offset)]
            arguments[:filter] = ["#{spec[:type]}Filter", filter]
            raise ArgumentError, "#{name} takes no order_by" if order_by && !spec[:order]

            arguments[:orderBy] = ["[#{spec[:type]}OrderBy!]", order_by && Array(order_by).map(&:to_s)]
            run_query(spec[:field], arguments, fields) || []
          end

          define_method(:"#{name}_count") do |filter: nil, **owner|
            arguments = owner_arguments(spec[:scope], owner, name)
            arguments[:filter] = ["#{spec[:type]}Filter", filter]
            run_query("#{spec[:field]}Count", arguments, nil)
          end

          next unless spec[:single]

          field = spec[:single].to_s.gsub(/_([a-z])/) { Regexp.last_match(1).upcase }
          define_method(spec[:single]) do |id, fields: spec[:fields]|
            run_query(field, { id: ["String!", id] }, fields)
          end
        end

        AGGREGATES.each do |name, (field, type, has_amount)|
          default_fields = "count #{AGGREGATE_METRICS if has_amount} " \
                           "groups { keys { dimension value } count #{AGGREGATE_METRICS if has_amount} } isTruncated"
          define_method(name) do |filter: nil, group_by: nil, granularity: nil, fields: default_fields|
            run_query(field, {
                        filter: ["#{type}Filter", filter],
                        groupBy: ["[#{type}Dimension!]", group_by && Array(group_by).map(&:to_s)],
                        granularity: ["TimeGranularity", granularity&.to_s]
                      }, fields)
          end
        end

        ANALYTICS.each do |name, field|
          define_method(name) do |fields:, start_date:, end_date:, currency: nil, status: nil, **owner|
            arguments = owner_arguments(:store_slug, owner, name)
            if arguments.values.all? { |_, value| value.nil? }
              raise ArgumentError, "#{name} needs store_id or store_slug"
            end

            arguments[:filter] = ["AnalyticsFilterInput!", analytics_filter(start_date, end_date, currency, status)]
            run_query(field, arguments, fields)
          end
        end

        def payout_analysis(fields:, start_date:, end_date:, merchant_id: nil, currency: nil, status: nil)
          run_query("payoutAnalysis", {
                      merchantId: ["String", merchant_id],
                      filter: ["AnalyticsFilterInput!", analytics_filter(start_date, end_date, currency, status)]
                    }, fields)
        end

        # Defaults to the configured store; pass `slug:` to find a store by slug instead.
        def store(id = nil, slug: nil, fields: STORE_FIELDS)
          id ||= @store_id unless slug
          raise ArgumentError, "id or slug is required" if blank?(id) && blank?(slug)

          run_query("store", { id: ["String", id], slug: ["String", slug] }, fields)
        end

        # The merchant the API key belongs to.
        def me(fields: MERCHANT_FIELDS)
          run_query("me", {}, fields)
        end

        def onetime_product_versions(product_id, fields: ONETIME_VERSION_FIELDS)
          run_query("onetimeProductVersions", { productId: ["String!", product_id] }, fields) || []
        end

        def subscription_product_versions(product_id, fields: SUBSCRIPTION_VERSION_FIELDS)
          run_query("subscriptionProductVersions", { productId: ["String!", product_id] }, fields) || []
        end

        def notification_recipients(store_id: @store_id, limit: nil, offset: nil, fields: RECIPIENT_FIELDS)
          run_query("storeNotificationRecipients", {
                      storeId: ["String!", require_store_id(store_id)],
                      limit: ["Int", limit && Integer(limit)],
                      offset: ["Int", offset && Integer(offset)]
                    }, fields) || []
        end

        def notification_recipients_count(store_id: @store_id)
          run_query("storeNotificationRecipientsCount", { storeId: ["String!", require_store_id(store_id)] }, nil)
        end

        private
          def owner_arguments(scope, owner, name)
            unknown = owner.keys - OWNER_KEYS.fetch(scope)
            # An unknown owner would be dropped, and the query would then read every store.
            raise ArgumentError, "#{name} does not take #{unknown.join(", ")}" unless unknown.empty?

            store_id = owner.fetch(:store_id, @store_id)
            case scope
            when :store then { storeId: ["String!", require_store_id(store_id)] }
            when :coupon
              raise ArgumentError, "#{name} needs coupon_id" if blank?(owner[:coupon_id])

              { couponId: ["String!", owner[:coupon_id]] }
            when :store_opt then { storeId: ["String", store_id] }
            when :store_slug
              # A slug names the store on its own, so the configured store must not join it.
              slug = owner[:store_slug]
              { storeId: ["String", slug ? nil : store_id], storeSlug: ["String", slug] }
            else {}
            end
          end

          # `arguments` is { name: [GraphQL type, value] }; a nil value leaves the argument out.
          def run_query(field, arguments, fields)
            given = arguments.reject { |_, (_, value)| value.nil? }
            declared = given.map { |name, (type, _)| "$#{name}: #{type}" }.join(", ")
            passed = given.keys.map { |name| "#{name}: $#{name}" }.join(", ")
            query = "query#{" (#{declared})" unless given.empty?} { #{field}#{"(#{passed})" unless given.empty?}" \
                    "#{" { #{fields} }" if fields} }"
            data = graphql(query, given.transform_values(&:last))
            data && data[field]
          end

          def analytics_filter(start_date, end_date, currency, status)
            filter = { timeRange: { startDate: time_string(start_date), endDate: time_string(end_date) } }
            filter[:currency] = currency if currency
            filter[:status] = status if status
            filter
          end

          def time_string(value)
            value.respond_to?(:utc) ? value.dup.utc.iso8601 : value.to_s
          end
      end
    end
  end
end
