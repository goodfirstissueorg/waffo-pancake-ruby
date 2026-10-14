# waffo-pancake

Ruby client for the [Waffo Pancake](https://docs.waffo.ai) merchant API. It signs requests with
your API key, creates checkout sessions, manages subscriptions and products, runs GraphQL
queries, and verifies webhook signatures. It is a Ruby port of the official TypeScript SDK,
[`@waffo/pancake-ts`](https://www.npmjs.com/package/@waffo/pancake-ts), built on the standard
library (`net/http`, `openssl`, `json`) plus the `base64` gem.

## Install

```ruby
gem "waffo-pancake"
```

## Configure

Settings come from `Waffo::Pancake.configure`, which starts from the `WAFFO_*` environment
variables (`WAFFO_MERCHANT_ID`, `WAFFO_PRIVATE_KEY`, `WAFFO_STORE_ID`, `WAFFO_ENVIRONMENT`):

```ruby
Waffo::Pancake.configure do |config|
  config.merchant_id = "MER_..."
  config.private_key = File.read("waffo.pem")
  config.store_id = "STO_..."
  config.environment = "prod"   # which webhook key to trust; nil tries prod, then test
end

Waffo::Pancake.client.cancel_subscription("ORD_...")   # a client built from the configuration
```

Or build a client yourself:

Create an API key in the Dashboard (**API & Development**). A key is bound to test or prod
when it is created, so the key decides the environment.

```ruby
require "waffo/pancake"

client = Waffo::Pancake::Client.new(
  merchant_id: ENV["WAFFO_MERCHANT_ID"],  # MER_...
  private_key: ENV["WAFFO_PRIVATE_KEY"],  # PEM, PEM with literal \n, or bare base64
  logger: Rails.logger                    # optional: one line per request, never the body
)
```

Both arguments default to those environment variables. Keep the private key on the server.

## Checkout

```ruby
# Authenticated checkout (recommended): buyer_identity is your stable id for the customer.
# Waffo uses it for trial eligibility and the customer portal.
session = client.create_authenticated_checkout(
  product_id: "PROD_...",
  currency: "USD",
  buyer_identity: "user-42",
  buyer_email: "ada@example.com",
  success_url: "https://example.com/settings?checkout=success",
  order_merchant_external_id: "user-42",   # comes back on every webhook for the order
  metadata: { "user_id" => "42" }
)
redirect_to session["checkoutUrl"], allow_other_host: true   # ends in #token=...

# Anonymous checkout: the buyer fills everything in on the page.
client.create_checkout_session(product_id: "PROD_...", currency: "USD")
```

Top-level keyword arguments may be snake_case and are sent as camelCase. Nested hashes
(`metadata`, `prices`, `billing_detail`'s fields) are sent exactly as given.

## Customer portal

A customer who is signed in on your site can enter the store's customer portal without an email
code. Use the `buyer_identity` you gave at authenticated checkout, taken from your own session.

```ruby
link = client.create_customer_portal_link(buyer_identity: current_user.id)  # store_id: defaults to WAFFO_STORE_ID
# => {"portalUrl" => "https://pancake.waffo.ai/consumer/portal/store/STO_...#token=...", "expiresAt" => "..."}
```

The URL is a bearer credential: make a new one on each click, answer with a 302 and
`Cache-Control: no-store` / `Referrer-Policy: no-referrer`, and never log, cache or email it.
The portal opens on the API key's environment. In Rails, the concern does all of that:

```ruby
class WaffoPortalController < ApplicationController
  include Waffo::Pancake::CustomerPortalController
  before_action :authenticate_user!

  def show
    redirect_to_waffo_customer_portal(buyer_identity: current_user.id)  # 502 if Waffo fails
  end
end
```

Link to that route with a plain `<a>`, so nothing prefetches it. Set a Website in the store
settings: the portal's return button links only there.

## Subscriptions

```ruby
client.cancel_subscription("ORD_...")      # => {"orderId" => "ORD_...", "status" => "canceling"}
client.reactivate_subscription("ORD_...")  # while still canceling
client.subscription_order("ORD_...")       # GraphQL; nil when unknown
# => {"status" => "active", "currentPeriodEnd" => "2027-10-08T...", "merchantProvidedBuyerIdentity" => "user-42", ...}
```

`canceling` keeps access until `currentPeriodEnd`. The terminal `canceled` arrives as a webhook.

## Products

```ruby
client.create_subscription_product(
  store_id: "STO_...", name: "Pro", billing_period: "yearly",
  prices: { "USD" => { amount: "9.99", taxCategory: "saas" } }
)
client.publish_subscription_product(id: "PROD_...")  # test → prod, first publish only
```

Amounts are display strings (`"9.99"`), not cents.

## GraphQL and other endpoints

```ruby
client.graphql("query ($id: String!) { onetimeOrder(id: $id) { id status } }", id: "ORD_...")
client.action("/v1/actions/refund-ticket/create-ticket", { payment_id: "PAY_...", reason: "..." })
```

## Webhooks

Pass the raw body; a body that was parsed and re-serialized will not verify.

```ruby
class WaffoWebhooksController < ActionController::Base
  skip_forgery_protection

  def create
    event = Waffo::Pancake::Webhook.verify(
      request.raw_post,
      request.headers["X-Waffo-Signature"],
      environment: "prod"            # or "test"; omit to try prod, then test
    )
    # Deduplicate on event.id: a retry redelivers the same id.
    case event.event_type
    when "order.completed" then                                 # record event.data.charged_amount
    when "subscription.activated", "subscription.renewed" then # grant access until data["currentPeriodEnd"]
    when "subscription.canceled" then                           # revoke access
    end
    head :ok
  rescue Waffo::Pancake::InvalidSignature
    head :unauthorized
  end
end
```

The platform's public keys are built in. When Waffo rotates them, set
`WAFFO_WEBHOOK_PROD_PUBLIC_KEY` / `WAFFO_WEBHOOK_TEST_PUBLIC_KEY` (or `WAFFO_WEBHOOK_PUBLIC_KEY` for
both), or pass `public_key:`. Timestamps may be up to 45 minutes old and 1 minute ahead by default
(`tolerance:`, `future_tolerance:`, in seconds; `tolerance: 0` turns the check off).

`Waffo::Pancake::Webhook::EVENT_TYPES` lists the event types.

### Amount fields

`verify` returns a `Waffo::Pancake::Webhook::Event`, a Hash with readers. Its `data` reads
the amount fields by what they describe:

| Reader | Field | Events |
|---|---|---|
| `charged_amount` | `chargedAmount` | Payment (`order.completed`, `subscription.payment_succeeded`): what the buyer was actually charged, after prorated credits, trials and zero-amount card checks |
| `list_price` | `listPrice` | Payment: the list price behind the charge (`total`, `subtotal`, `taxAmount`, `taxRate`, `taxName`) |
| `refunded_amount` | `refundedAmount` | `refund.*`: what this refund returned |
| `original_charged_amount` | `originalChargedAmount` | `refund.*`: what the refunded payment actually collected, the most a refund can reach |
| `original_payment` | `originalPayment` | `refund.*`: the refunded payment's list price |
| `plan_price` | `planPrice` | Other `subscription.*` events: the plan's price for the current period |
| `period_number`, `first_period?`, `renewal?` | `periodNumber` | Subscription events, `subscription.payment_succeeded` and subscription refunds: 1 for the first period, N for the Nth renewal |

`chargedAmount`, `refundedAmount` and `originalChargedAmount` are absent (nil) when the payment
channel reported no amount. `periodNumber` counts failed charges too, is `0` before a scheduled
plan change takes effect, and is not a deduplication key.

`amount`, `total`, `subtotal`, `taxAmount`, `taxRate` and `taxName` are deprecated: one name meant
a different amount per event family. Waffo sends them until its next major API version, not
before 2027-09-20. Since 2026-09-21, `amount` on payment events is the charged amount, so a check
such as `amount == total` fails there. Reading one of them with `[]`, `fetch` or `dig` still
returns the value, and reports the field to read instead for that event type:

```
DEPRECATION WARNING: Waffo webhook data["amount"] is deprecated on refund.succeeded; read data["refundedAmount"] instead. ...
```

Outside Rails each message is printed once per process with `Kernel#warn`. In Rails it goes to
`Rails.application.deprecators[:waffo_pancake]`, so `config.active_support.deprecation` applies
(`:raise` in tests finds every place to change). Set `config.deprecator` to any object answering
`warn(message, callstack)`, or to nil to turn the warnings off. A stored payload (or one that went
through a job) is a plain Hash again: `Waffo::Pancake::Webhook::Event.wrap(payload)` brings the
readers and warnings back.

### Delivery records

```ruby
client.webhook_deliveries(status: :failed, limit: 20)  # store_id: defaults to WAFFO_STORE_ID
# => [{"id" => ..., "eventType" => ..., "status" => "failed", "httpStatus" => 500, "attemptCount" => 4,
#      "payload" => ..., "responseBody" => ..., "lastAttemptedAt" => ..., ...}]
client.webhook_deliveries_count(status: :failed)
client.webhook_deliveries(event_type: "refund.succeeded", filter: { createdAt: { gte: 1.week.ago } }, offset: 20)
```

Waffo retries a delivery 3 times and has no manual redelivery. To process a failed one again,
run your own handler on its payload:

```ruby
client.webhook_deliveries(status: :failed).each do |delivery|
  HandleWaffoEventJob.perform_later(Waffo::Pancake::Webhook::Event.wrap(delivery["payload"]))
end
```

## Rails

Inside a Rails app the gem configures itself. Settings are read in this order, the last one
winning: `WAFFO_*` environment variables, `credentials.waffo`, `config.waffo_pancake`, then
`Waffo::Pancake.configure` in an initializer. The logger is `Rails.logger`, `private_key`
is added to `filter_parameters`, and redirects to a URL with `#token=` (authenticated checkout,
customer portal) to `filter_redirect`.

```yaml
# bin/rails credentials:edit
waffo:
  merchant_id: MER_...
  private_key: "-----BEGIN PRIVATE KEY-----\n..."
  store_id: STO_...
  environment: prod
```

```sh
bin/rails generate waffo_pancake:install          # add --skip-events-table to leave out the table
bin/rails db:migrate
```

The generator adds `config/initializers/waffo_pancake.rb`, a `POST /webhooks/waffo` route, and
`WaffoWebhooksController`. Unless `--skip-events-table` is given it also adds a
`waffo_webhook_events` table (one row per delivery id, so a retry is not handled twice), its
model and a `WaffoWebhookJob` to fill in.

The controller uses the `Waffo::Pancake::WebhookController` concern, which you can also include
in your own controller:

```ruby
class WaffoWebhooksController < ActionController::Base
  include Waffo::Pancake::WebhookController

  def create
    HandleWaffoEventJob.perform_later(waffo_event)   # verified Webhook::Event; wrap it again in the job
    head :ok
  end
end
```

Before the action the concern:

- verifies `X-Waffo-Signature` with the configured key, and answers 401 if it fails;
- answers 413 for a body over 256 KB;
- answers 200 without running the action when the delivery is for another `environment` or `store_id` (when those are configured), since an error status only makes Waffo retry it;
- keeps the payload out of `params` and the request log.

### Instrumentation

With ActiveSupport loaded (or any object answering `instrument(name, payload) { }` set as
`config.instrumenter`), the gem reports:

| Event | Payload |
|---|---|
| `request.waffo_pancake` | `method`, `path`, `status` (nil when there was no answer), `exception` when raised |
| `verify_webhook.waffo_pancake` | `environment`, `event_id`, `event_type`, `mode`, `exception` when refused |

```ruby
ActiveSupport::Notifications.subscribe("request.waffo_pancake") do |event|
  Rails.logger.info("Waffo #{event.payload[:path]} #{event.payload[:status]} #{event.duration.round}ms")
end
```

### Testing

```ruby
# spec/rails_helper.rb (or test/test_helper.rb with ActiveSupport::TestCase)
require "waffo/pancake/test_helpers"
RSpec.configure { |config| config.include Waffo::Pancake::TestHelpers }

it "accepts a signed delivery" do
  body = waffo_webhook_event("subscription.activated", data: { "orderId" => "ORD_1" }).to_json
  with_waffo_webhook_key { post "/webhooks/waffo", params: body, headers: waffo_webhook_headers(body) }
  expect(response).to have_http_status(:ok)
end

it "cancels at Waffo" do
  with_fake_waffo_client(Waffo::Pancake::TestHelpers::FakeClient.new("ORD_1" => { "status" => "active" })) do |waffo|
    post "/billing/cancel"
    expect(waffo.calls).to include([:cancel_subscription, "ORD_1"])
  end
end
```

`FakeClient` answers `subscription_order` from the orders it was given, moves an order to
`canceling` / `active` on cancel / reactivate, records every call in `calls`, and raises
`fail_with` when set.

## Errors

| Class | When |
|---|---|
| `Waffo::Pancake::Rejected` | Waffo refused the request (4xx other than 429). `status` and `errors` carry the details. |
| `Waffo::Pancake::Unavailable` | Network failure, timeout, 429 or 5xx. Worth retrying later. |
| `Waffo::Pancake::ConfigurationError` | Missing merchant id, or a key that does not parse. |
| `Waffo::Pancake::InvalidSignature` | A webhook that does not verify. |

All inherit from `Waffo::Pancake::Error`.

## Testing your code

`Client.new` takes a `transport:` callable that replaces the HTTP call. It receives the URI,
the headers and the JSON body and returns `[status, body]`.

```ruby
transport = ->(uri, headers, json) { [200, '{"data":{"orderId":"ORD_1","status":"canceling"}}'] }
client = Waffo::Pancake::Client.new(merchant_id: "MER_x", private_key: key, transport: transport)
```

Test cards: `4576 7500 0000 0110` succeeds and `4576 7500 0000 0220` is declined.

## Development

```sh
bundle install
bundle exec rake test        # test:core (no Rails loaded) and test:rails
```

Releases are published to RubyGems by the `Release` workflow when a `v*` tag is pushed (see
[RELEASING.md](RELEASING.md)). It uses
[trusted publishing](https://guides.rubygems.org/trusted-publishing/), so no API key is stored.

## License

MIT
