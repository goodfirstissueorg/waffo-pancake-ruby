# frozen_string_literal: true

module Waffo
  module Pancake
    # Base class. `status` is the HTTP status (nil when the request never got an answer) and
    # `errors` the envelope's `errors` array, as Waffo sent it.
    class Error < StandardError
      attr_reader :status, :errors

      def initialize(message = nil, status: nil, errors: [])
        super(message)
        @status = status
        @errors = errors
      end
    end

    # The key, merchant id or other setting is missing or unusable.
    class ConfigurationError < Error; end

    # Worth another try later: a network failure, a timeout, a 429 or a 5xx.
    class Unavailable < Error; end

    # Not worth another try as is: Waffo refused the request (validation, state, auth).
    class Rejected < Error; end

    # A webhook whose signature, header or timestamp does not check out.
    class InvalidSignature < Error; end
  end
end
