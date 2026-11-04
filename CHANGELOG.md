# Changelog

## 0.4.0

- Every endpoint in Waffo's API reference now has a method:
  - Stores: `create_store`, `update_store`, `delete_store`.
  - Store members: `add_store_merchant`, `remove_store_merchant`, `update_store_merchant_role`.
  - Webhooks: `update_webhook`.
  - Notification recipients: `add_notification_recipient`, `update_notification_recipient`,
    `remove_notification_recipient`.
  - Products: `update_onetime_product`, `publish_onetime_product`,
    `update_onetime_product_status`, `update_subscription_product_status`.
  - Product groups: `create_subscription_product_group`, `update_…`, `delete_…`, `publish_…`.
  - Promotions: `create_coupon`, `update_coupon`, `deactivate_coupon`, `create_promotion_code`,
    `generate_promotion_codes`, `deactivate_promotion_code`.
  - Refund tickets: `create_refund_ticket`, `resubmit_refund_ticket`.
  - Plan changes: `create_plan_change_session`, `create_authenticated_plan_change`.
  - Content safety: `scan_prompt`.
- `Client#customer(token, environment:)` returns a `CustomerSession`, authenticated with a session
  token, with the customer actions plus `create_onetime_order` and `create_subscription_order`.
- `StoreCheckout.new(store_slug:, environment:)` for anonymous checkout with only the store slug.
- GraphQL readers, generated from the schema that introspection reports: lists, `*_count` and
  single-record methods, `*_aggregate` methods and analytics methods. Filters travel as typed
  variables.
- `idempotency_key:` on every action, sent as `X-Idempotency-Key`.
- `Waffo::Pancake::NULL` sends an explicit JSON null, which clears a field. A nil is still dropped.
- `Error#retry_after`, from the `Retry-After` header.
- An action's result has a `"warnings"` key when Waffo sent warnings.
- `Client.new(environment:)`, defaulting to the configured environment.
- `TestHelpers::FakeClient` has every API method, generated, so a new endpoint cannot be missing.
- Changed: `graphql` now raises on a non-2xx status without `errors`. It used to return nil.
- Known: with an API key, `reactivate_subscription` and `cancel_onetime_order` get a 401 from
  Waffo's gateway. Call them through `client.customer(token)`.
- `rake test:live` runs the real API with a test-mode key. It is not part of `rake test`.

## 0.3.0

- Webhook amount fields (Waffo, 2026-09-20 to 2026-09-22):
  - `Webhook.verify` and `Waffo::Pancake.verify_webhook` return a `Webhook::Event`, a Hash
    subclass, so code that reads it as a Hash keeps working. `Webhook::Event.wrap` makes one from
    a stored payload (Hash or JSON).
  - `event.data` readers for the new fields: `charged_amount`, `refunded_amount`,
    `original_charged_amount`, `list_price`, `original_payment`, `plan_price`, `price`,
    `period_number`, `first_period?`, `renewal?`.
  - Reading a deprecated field (`amount`, `total`, `subtotal`, `taxAmount`, `taxRate`, `taxName`)
    with `[]`, `fetch` or `dig` reports a deprecation warning naming its replacement for that
    event type. `config.deprecator` chooses where it goes: a once-per-message `Kernel#warn` by
    default, `Rails.application.deprecators[:waffo_pancake]` in Rails, nil for none.
  - `Webhook::DEPRECATED_FIELDS`, `PAYMENT_EVENT_TYPES`, `REFUND_EVENT_TYPES` and
    `Webhook.family`.
- Customer portal sign-in without an email code: `Client#create_customer_portal_link`
  (`issue-session-token` with `purpose: "portal"`), `issue_session_token(purpose:)`, and the
  `Waffo::Pancake::CustomerPortalController` Rails concern, which answers with a 302 and
  `Cache-Control: no-store` / `Referrer-Policy: no-referrer`. The Railtie adds `#token=` to
  `filter_redirect`, so these URLs stay out of the request log.
- Webhook delivery records: `Client#webhook_deliveries` and `#webhook_deliveries_count`, with
  `status:`, `event_type:`, `filter:`, `limit:` and `offset:`. Waffo has no redelivery API;
  run your handler on `Webhook::Event.wrap(delivery["payload"])` instead.
- `Client.new(store_id:)`, defaulting to the configured store, for the calls above.
- `TestHelpers::FakeClient#create_customer_portal_link` and `#webhook_deliveries`.
- The generated `WaffoWebhookEvent#data` and `#waffo_event` wrap the stored payload; the
  generated job reads the new amount fields.

## 0.2.1

- `Client#subscription_order` also returns the order's current product as `productId`, read
  from `subscriptionProduct { id }`, so a plan change to another product can be detected.

## 0.2.0

- `Waffo::Pancake.configure` / `.configuration`: process-wide settings that start from the
  `WAFFO_*` environment variables, a shared `Waffo::Pancake.client`, and
  `Waffo::Pancake.verify_webhook` using the configured environment, key and tolerances.
  `Client.new` arguments now default to the configuration (still the environment variables when
  nothing is configured).
- Rails integration, loaded only inside a Rails app:
  - A Railtie that reads `credentials.waffo` and `config.waffo_pancake`, logs to `Rails.logger`
    and filters `private_key` from logs.
  - `Waffo::Pancake::WebhookController`, a controller concern that verifies the signature
    before the action, keeps the payload out of params and the request log, and acknowledges
    deliveries for another environment or store without running the action.
  - `bin/rails generate waffo_pancake:install`: initializer, route, webhook controller, and
    (unless `--skip-events-table`) a `waffo_webhook_events` table, model and job.
- Instrumentation: `request.waffo_pancake` for each API request and
  `verify_webhook.waffo_pancake` for each webhook check, through ActiveSupport::Notifications
  when it is loaded or any `instrumenter` you configure.
- `Waffo::Pancake::TestHelpers`: signed webhook headers for a throwaway key, event builders, and
  `FakeClient` to stand in for the API.

## 0.1.0

- `Waffo::Pancake::Client`: signed merchant API requests (RSA-SHA256, `X-Merchant-Id` /
  `X-Timestamp` / `X-Signature`), checkout sessions (anonymous and authenticated), subscription
  cancel and reactivate, one-time order cancel, subscription and one-time products, webhook
  endpoints, GraphQL and `subscription_order`.
- `Waffo::Pancake::Webhook.verify`: `X-Waffo-Signature` verification with the built-in test and
  prod platform keys, environment-variable overrides and replay tolerance.
- Private and public keys accepted as PEM, PEM with literal `\n`, or bare base64.
