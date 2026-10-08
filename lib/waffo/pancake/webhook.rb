# frozen_string_literal: true

require "base64"
require "json"
require "openssl"

module Waffo
  module Pancake
    # Verifies a delivery the way @waffo/pancake-ts's verifyWebhook does.
    #
    #   event = Waffo::Pancake::Webhook.verify(request.raw_post, request.headers["X-Waffo-Signature"],
    #                                          environment: "prod")
    #   event["eventType"] # => "subscription.activated"
    #
    # The header is `t=<unix ms>,v1=<base64>`: an RSA-SHA256 signature over "<t>.<raw body>".
    # Pass the body exactly as received; a re-serialized JSON will not verify.
    module Webhook
      SIGNATURE_HEADER = "X-Waffo-Signature"

      # Retries reuse the first attempt's header, so the past-facing window covers a whole
      # retry schedule. Deduplicate on the event's `id`; the window only bounds replays.
      DEFAULT_TOLERANCE = 45 * 60
      DEFAULT_FUTURE_TOLERANCE = 60

      ENVIRONMENTS = %w[test prod].freeze

      # Waffo's platform keys, as embedded in @waffo/pancake-ts 0.25.0.
      PUBLIC_KEYS = {
        "test" => <<~PEM,
          -----BEGIN PUBLIC KEY-----
          MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAxnmRY6yMMA3lVqmAU6ZG
          b1sjL/+r/z6E+ZjkXaDAKiqOhk9rpazni0bNsGXwmftTPk9jy2wn+j6JHODD/WH/
          SCnSfvKkLIjy4Hk7BuCgB174C0ydan7J+KgXLkOwgCAxxB68t2tezldwo74ZpXgn
          F49opzMvQ9prEwIAWOE+kV9iK6gx/AckSMtHIHpUesoPDkldpmFHlB2qpf1vsFTZ
          5kD6DmGl+2GIVK01aChy2lk8pLv0yUMu18v44sLkO5M44TkGPJD9qG09wrvVG2wp
          OTVCn1n5pP8P+HRLcgzbUB3OlZVfdFurn6EZwtyL4ZD9kdkQ4EZE/9inKcp3c1h4
          xwIDAQAB
          -----END PUBLIC KEY-----
        PEM
        "prod" => <<~PEM
          -----BEGIN PUBLIC KEY-----
          MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAz+xApdTIb4ua+DgZKQ54
          iBsD82ybyhGCLRETONW4Jgbb3A8DUM1LqBk6r/CmTOCHqLalTQHNigvP3R5zkDNX
          iRJz6gA4MJ/+8K0+mnEE2RISQzN+Qu65TNd6svb+INm/kMaftY4uIXr6y6kchtTJ
          dwnQhcKdAL2v7h7IFnkVelQsKxDdb2PqX8xX/qwd01iXvMcpCCaXovUwZsxH2QN5
          ZKBTseJivbhUeyJCco4fdUyxOMHe2ybCVhyvim2uxAl1nkvL5L8RCWMCAV55LLo0
          9OhmLahz/DYNu13YLVP6dvIT09ZFBYU6Owj1NxdinTynlJCFS9VYwBgmftosSE1U
          dwIDAQAB
          -----END PUBLIC KEY-----
        PEM
      }.freeze

      EVENT_TYPES = %w[
        order.completed
        subscription.activated subscription.payment_succeeded subscription.renewed subscription.recovered
        subscription.plan_changed subscription.plan_change_scheduled subscription.plan_change_failed
        subscription.canceling subscription.uncanceled subscription.canceled subscription.past_due
        refund.succeeded refund.failed
      ].freeze

      module_function

      # Returns the parsed event. Raises InvalidSignature.
      #
      # environment: "test" or "prod" uses that environment's key; nil tries prod, then test.
      # public_key:  a key to use instead (skips the lookup and `environment`).
      # tolerance:   seconds a timestamp may lie in the past; 0 skips the timestamp check.
      def verify(payload, signature_header, environment: nil, public_key: nil, tolerance: DEFAULT_TOLERANCE,
                 future_tolerance: DEFAULT_FUTURE_TOLERANCE, now: Time.now)
        timestamp, signature = parse_header(signature_header)
        check_timestamp!(timestamp, now, tolerance, future_tolerance) if tolerance.positive?

        input = "#{timestamp}.#{payload}"
        keys = public_key ? [Keys.public_key(public_key)] : keys_for(environment)
        raise InvalidSignature, "Invalid webhook signature" unless keys.any? { |key| valid?(key, signature, input) }

        JSON.parse(payload.to_s)
      rescue JSON::ParserError
        raise InvalidSignature, "Webhook body is not JSON"
      end

      # The key for an environment: WAFFO_WEBHOOK_{TEST,PROD}_PUBLIC_KEY, then
      # WAFFO_WEBHOOK_PUBLIC_KEY, then the built-in platform key.
      def public_key_for(environment)
        environment = environment.to_s
        raise ArgumentError, "environment must be test or prod" unless ENVIRONMENTS.include?(environment)

        custom = ENV["WAFFO_WEBHOOK_#{environment.upcase}_PUBLIC_KEY"] || ENV["WAFFO_WEBHOOK_PUBLIC_KEY"]
        Keys.public_key(custom.to_s.strip.empty? ? PUBLIC_KEYS.fetch(environment) : custom)
      end

      def keys_for(environment)
        environment ? [public_key_for(environment)] : [public_key_for("prod"), public_key_for("test")]
      end

      def parse_header(header)
        raise InvalidSignature, "Missing #{SIGNATURE_HEADER} header" if header.nil? || header.to_s.strip.empty?

        parts = header.to_s.split(",").each_with_object({}) do |pair, out|
          key, value = pair.split("=", 2)
          out[key.strip] = value.strip if value
        end
        timestamp, signature = parts["t"], parts["v1"]
        if timestamp.to_s.empty? || signature.to_s.empty?
          raise InvalidSignature, "Malformed #{SIGNATURE_HEADER} header: missing t or v1"
        end

        [timestamp, signature]
      end

      def check_timestamp!(timestamp, now, tolerance, future_tolerance)
        raise InvalidSignature, "Invalid timestamp in #{SIGNATURE_HEADER} header" unless timestamp.match?(/\A\d+\z/)

        age = now.to_f - (timestamp.to_i / 1000.0)
        return if age <= tolerance && age >= -future_tolerance

        raise InvalidSignature, "Webhook timestamp outside tolerance window (possible replay attack)"
      end

      def valid?(key, signature, input)
        key.verify(OpenSSL::Digest::SHA256.new, Base64.strict_decode64(signature), input)
      rescue ArgumentError, OpenSSL::PKey::PKeyError
        false
      end
    end
  end
end
