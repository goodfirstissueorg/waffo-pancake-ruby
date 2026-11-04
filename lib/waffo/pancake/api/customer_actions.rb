# frozen_string_literal: true

module Waffo
  module Pancake
    module API
      # Actions that act for one customer, so both Client and CustomerSession have them.
      #
      # The gateway decides which credential a route takes, and the two groups below differ:
      # with an API key, reactivate-order and onetime-order/cancel-order answer 401 "API Key
      # authentication not supported for this route" (tested on 2026-11-04). They stay here so
      # the 0.x Client API keeps its shape, and because Waffo can open these routes later.
      module CustomerActions
        def create_checkout_session(product_id:, currency:, **params)
          action("/v1/actions/checkout/create-session", product_id: product_id, currency: currency, **params)
        end

        # A checkout session that changes the plan of `origin_order_id`. Without a coupon of its
        # own, the session follows the rules of the origin order's product group.
        def create_plan_change_session(origin_order_id:, product_id:, currency:, **params)
          action("/v1/actions/checkout/create-session", origin_order_id: origin_order_id, product_id: product_id,
                                                        currency: currency, **params)
        end

        # pending → canceled at once; active, trialing and past_due → canceling, ending with the
        # paid period. The terminal `canceled` arrives later as a webhook. Optional: cancel_reason,
        # cancel_comment.
        def cancel_subscription(order_id, **params)
          action("/v1/actions/subscription-order/cancel-order", order_id: order_id, **params)
        end

        # Undoes a cancellation while the order is still `canceling`. Session token only; see the
        # module comment.
        def reactivate_subscription(order_id, **params)
          action("/v1/actions/subscription-order/reactivate-order", order_id: order_id, **params)
        end

        # Session token only; see the module comment.
        def cancel_onetime_order(order_id, **params)
          action("/v1/actions/onetime-order/cancel-order", order_id: order_id, **params)
        end

        # requested_amount: { amount: "9.99", currency: "USD" }
        def create_refund_ticket(payment_id:, reason:, requested_amount:, **params)
          action("/v1/actions/refund-ticket/create-ticket", payment_id: payment_id, reason: reason,
                                                            requested_amount: requested_amount, **params)
        end

        def resubmit_refund_ticket(ticket_id:, reason:, requested_amount:, **params)
          action("/v1/actions/refund-ticket/resubmit-ticket", ticket_id: ticket_id, reason: reason,
                                                              requested_amount: requested_amount, **params)
        end
      end
    end
  end
end
