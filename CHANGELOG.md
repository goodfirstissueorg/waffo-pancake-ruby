# Changelog

## 0.1.0

- `Waffo::Pancake::Client`: signed merchant API requests (RSA-SHA256, `X-Merchant-Id` /
  `X-Timestamp` / `X-Signature`), checkout sessions (anonymous and authenticated), subscription
  cancel and reactivate, one-time order cancel, subscription and one-time products, webhook
  endpoints, GraphQL and `subscription_order`.
- `Waffo::Pancake::Webhook.verify`: `X-Waffo-Signature` verification with the built-in test and
  prod platform keys, environment-variable overrides and replay tolerance.
- Private and public keys accepted as PEM, PEM with literal `\n`, or bare base64.
