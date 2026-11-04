# frozen_string_literal: true

require "json"

module Waffo
  module Pancake
    # Sends an explicit JSON null in an update, which clears the field. A plain nil is dropped,
    # so a variable that happens to be nil can never erase data at Waffo.
    NULL = Object.new
    class << NULL
      def to_json(*) = "null"
      def inspect = "Waffo::Pancake::NULL"
    end
    NULL.freeze

    # The request logic shared by Client, CustomerSession and StoreCheckout. An includer defines
    # `auth_headers(path, json)` and `connection`.
    #
    # Waffo refuses a request that carries two authentication methods, so an includer sends the
    # headers of one method only.
    module Requests
      IDEMPOTENCY_KEY = /\A[A-Za-z0-9_-]{1,256}\z/

      # Any action endpoint. Returns the envelope's `data`, plus a "warnings" key when Waffo sent
      # any. Raises Rejected or Unavailable on `errors` or a non-2xx status.
      #
      # Top-level keys are sent in camelCase and nil values are dropped; use NULL to clear a field.
      # `idempotency_key:` is sent as X-Idempotency-Key. Waffo keeps the answer for 24 hours.
      def action(path, params = {}, **named)
        params = params.merge(named)
        key = params.delete(:idempotency_key)
        response = post(path, camelize(params), idempotency_headers(key))
        succeeded = !present?(response.envelope["errors"]) && (200..299).cover?(response.status)
        connection.fail_with(path, response) unless succeeded

        with_warnings(response.envelope)
      end

      # Returns `data`. Raises when the response carries `errors` and no data, or on a non-2xx
      # status. Partial data comes back as is, because the fields Waffo did answer are still valid.
      def graphql(query, variables = {})
        path = "/v1/graphql"
        response = post(path, { "query" => query, "variables" => variables })
        envelope = response.envelope
        failed = (present?(envelope["errors"]) && envelope["data"].nil?) || !(200..299).cover?(response.status)
        connection.fail_with(path, response) if failed

        envelope["data"]
      end

      def self.environment!(value)
        value = value.to_s.strip.downcase
        return value if Configuration::ENVIRONMENTS.include?(value)

        raise ConfigurationError, "environment must be test or prod, got #{value.inspect}"
      end

      private
        def post(path, params, extra_headers = {})
          json = JSON.generate(params)
          headers = { "Content-Type" => "application/json" }.merge(auth_headers(path, json)).merge(extra_headers)
          connection.post(path, headers, json)
        end

        def idempotency_headers(key)
          return {} if key.nil?
          return { "X-Idempotency-Key" => key } if key.is_a?(String) && key.match?(IDEMPOTENCY_KEY)

          raise ArgumentError, "idempotency_key must be 1 to 256 characters from A-Z a-z 0-9 _ -"
        end

        def with_warnings(envelope)
          data = envelope["data"] || {}
          warnings = envelope["warnings"]
          data.is_a?(Hash) && present?(warnings) ? data.merge("warnings" => warnings) : data
        end

        def camelize(params)
          params.each_with_object({}) do |(key, value), out|
            next if value.nil?

            out[key.to_s.gsub(/_([a-z\d])/) { Regexp.last_match(1).upcase }] = value.equal?(NULL) ? nil : value
          end
        end

        def blank?(value) = value.nil? || value.to_s.strip.empty?

        def present?(value) = !(value.nil? || (value.respond_to?(:empty?) && value.empty?))
    end
  end
end
