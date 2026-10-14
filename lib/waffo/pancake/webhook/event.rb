# frozen_string_literal: true

require "json"

module Waffo
  module Pancake
    module Webhook
      PAYMENT_EVENT_TYPES = %w[order.completed subscription.payment_succeeded].freeze
      REFUND_EVENT_TYPES = %w[refund.succeeded refund.failed].freeze

      # The six `data` fields whose name meant a different thing per event family, with the field
      # that replaces each on payment, refund and subscription events. Waffo keeps sending them
      # until the next major API version, not before DEPRECATED_FIELDS_REMOVAL.
      DEPRECATED_FIELDS = {
        "amount" => { payment: "chargedAmount", refund: "refundedAmount", subscription: "planPrice.total" },
        "total" => { payment: "listPrice.total", refund: "originalPayment.total", subscription: "planPrice.total" },
        "subtotal" => { payment: "listPrice.subtotal", refund: "originalPayment.subtotal",
                        subscription: "planPrice.subtotal" },
        "taxAmount" => { payment: "listPrice.taxAmount", refund: "originalPayment.taxAmount",
                         subscription: "planPrice.taxAmount" },
        "taxRate" => { payment: "listPrice.taxRate", refund: "originalPayment.taxRate",
                       subscription: "planPrice.taxRate" },
        "taxName" => { payment: "listPrice.taxName", refund: "originalPayment.taxName",
                       subscription: "planPrice.taxName" }
      }.freeze
      DEPRECATED_FIELDS_REMOVAL = "2027-09-20"

      module_function

      # :payment (one charge), :refund, :subscription (a subscription's status), or nil.
      def family(event_type)
        event_type = event_type.to_s
        return :payment if PAYMENT_EVENT_TYPES.include?(event_type)
        return :refund if REFUND_EVENT_TYPES.include?(event_type)

        :subscription if event_type.start_with?("subscription.")
      end

      # A delivery as a Hash, with readers for the envelope. `data` is an EventData, which warns
      # through Waffo::Pancake::Deprecation when a deprecated field is read.
      #
      #   event = Waffo::Pancake::Webhook::Event.wrap(stored_payload)  # Hash or JSON String
      #   event.data.charged_amount                                     # => "9.00"
      class Event < Hash
        # `payload` is a Hash (string or symbol keys) or its JSON. Use it on a delivery you stored
        # or read back with Client#webhook_deliveries; it does not check a signature.
        def self.wrap(payload)
          return payload if payload.is_a?(Event)

          payload = JSON.parse(payload) if payload.is_a?(String)
          raise ArgumentError, "webhook event must be a Hash, got #{payload.class}" unless payload.respond_to?(:to_hash)

          event = new.replace(payload.to_hash.transform_keys(&:to_s))
          event["data"] = EventData.new(event["data"], event["eventType"]) if event["data"].respond_to?(:to_hash)
          event
        end

        # The delivery id: the same on every retry, so deduplicate on it.
        def id = self["id"]
        def event_type = self["eventType"]
        def event_id = self["eventId"]
        def store_id = self["storeId"]
        def mode = self["mode"]
        def test? = mode == "test"
        def timestamp = self["timestamp"]
        def data = self["data"] || EventData.new({}, event_type)
        def family = Webhook.family(event_type)
        def payment? = family == :payment
        def refund? = family == :refund
        def subscription? = family == :subscription
      end

      # The `data` of a delivery. Reading `amount`, `total`, `subtotal`, `taxAmount`, `taxRate` or
      # `taxName` with [], fetch or dig still answers the value, and reports the field to read
      # instead. Iterating, serializing and `key?` report nothing.
      class EventData < Hash
        attr_reader :event_type

        def initialize(fields = {}, event_type = nil)
          super()
          replace(fields.to_hash.transform_keys(&:to_s))
          @event_type = event_type
        end

        def [](key)
          deprecated_read(key)
          super
        end

        def fetch(key, *default, &block)
          deprecated_read(key)
          super
        end

        def dig(key, *keys)
          deprecated_read(key)
          super
        end

        def order_id = self["orderId"]
        def currency = self["currency"]

        # What this charge actually took, after prorated credits, trials and zero-amount card
        # checks. Payment events only; nil when the payment channel reported no amount.
        def charged_amount = self["chargedAmount"]

        # What this refund returned. Refund events only; nil when the channel reported no amount.
        def refunded_amount = self["refundedAmount"]

        # What the refunded payment actually collected: the most a refund can reach. Refund
        # events only; nil when the channel reported no amount for that payment.
        def original_charged_amount = self["originalChargedAmount"]

        # Breakdowns (total, subtotal, taxAmount, taxRate, taxName), each on one event family.
        def list_price = self["listPrice"]
        def original_payment = self["originalPayment"]
        def plan_price = self["planPrice"]

        # The breakdown this event's figures refer to, whatever its family.
        def price = list_price || original_payment || plan_price

        # The payment channel's billing period: 1 for the first, N for the Nth renewal. A failed
        # charge uses a period too; 0 is authorized but not charged yet. On refunds, the period of
        # the refunded charge. Nil on one-time orders and on older subscriptions. Not unique per
        # event: deduplicate on the event id.
        def period_number = self["periodNumber"]
        def first_period? = period_number == 1
        def renewal? = period_number.is_a?(Integer) && period_number > 1

        private
          def deprecated_read(key)
            replacements = DEPRECATED_FIELDS[key.to_s]
            return unless replacements

            Deprecation.warn(deprecation_message(key.to_s, replacements), caller_locations(2))
          end

          def deprecation_message(key, replacements)
            family = Webhook.family(event_type)
            instead = if family
                        reader(replacements.fetch(family))
                      else
                        replacements.map { |name, field| "#{reader(field)} on #{name} events" }.join(", ")
                      end
            "Waffo webhook data[#{key.inspect}] is deprecated#{" on #{event_type}" if family}; read #{instead} " \
              "instead. Waffo removes it in its next major API version, not before #{DEPRECATED_FIELDS_REMOVAL}."
          end

          def reader(field)
            parts = field.split(".")
            parts.one? ? "data[#{field.inspect}]" : "data.dig(#{parts.map(&:inspect).join(", ")})"
          end
      end
    end
  end
end
