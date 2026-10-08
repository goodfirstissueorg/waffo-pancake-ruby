# Changelog

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
