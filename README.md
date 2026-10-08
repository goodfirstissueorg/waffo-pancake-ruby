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
    # Deduplicate on event["id"]: a retry redelivers the same id.
    case event["eventType"]
    when "subscription.activated", "subscription.renewed" then # grant access until data.currentPeriodEnd
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
bundle exec rake test
```

Releases are published to RubyGems by the `Release` workflow when a `v*` tag is pushed. It uses
[trusted publishing](https://guides.rubygems.org/trusted-publishing/), so no API key is stored.

## License

MIT
