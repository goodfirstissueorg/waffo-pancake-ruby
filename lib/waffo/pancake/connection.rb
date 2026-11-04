# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "time"
require "uri"

module Waffo
  module Pancake
    # One POST to Waffo: HTTP, instrumentation, the log line and envelope parsing. It knows
    # nothing about authentication, so all three entry points share it.
    #
    # Invariant: the body and the headers are never logged or instrumented, because they hold
    # credentials and buyer data.
    class Connection
      NETWORK_ERRORS = [
        Timeout::Error, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError, Net::HTTPBadResponse
      ].freeze

      Response = Struct.new(:status, :envelope, :headers)

      # `transport` takes the URI, the headers and the JSON body and answers `[status, body]` or
      # `[status, body, headers]`.
      def initialize(base_url:, timeout:, logger: nil, instrumenter: nil, transport: nil)
        @base_url = base_url.to_s.chomp("/")
        @timeout = timeout
        @logger = logger
        @instrumenter = instrumenter
        @transport = transport || method(:http_post)
      end

      attr_reader :base_url

      def post(path, headers, json)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        status, body, response_headers = instrument("request.waffo_pancake", method: "POST", path: path) do |payload|
          call_transport(URI("#{@base_url}#{path}"), headers, json).tap { |answer| payload[:status] = answer.first }
        end
        elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(2)
        @logger&.info("[Waffo] POST #{path} status=#{status.inspect} in #{elapsed}s")

        raise Unavailable.new("Waffo #{path} unreachable: #{body}", status: nil) if status.nil?

        envelope = parse(body)
        response = Response.new(status, envelope.is_a?(Hash) ? envelope : {}, response_headers || {})
        fail_with(path, response, "non-JSON response") unless envelope.is_a?(Hash)

        warn_about(path, response)
        response
      end

      def fail_with(path, response, fallback = "request failed")
        errors = Array(response.envelope["errors"])
        message = errors.map { |e| e.is_a?(Hash) ? e["message"] : e.to_s }.compact.first || fallback
        status = response.status
        error = status == 429 || status >= 500 ? Unavailable : Rejected
        raise error.new("Waffo #{path} status=#{status}: #{message}", status: status, errors: errors,
                                                                       retry_after: retry_after(response.headers))
      end

      private
        def warn_about(path, response)
          warnings = response.envelope["warnings"]
          return if warnings.nil? || warnings.empty?

          @logger&.warn("[Waffo] POST #{path} warnings=#{warnings.size}")
        end

        # Seconds to wait, from delay-seconds or an HTTP-date. Nil when the header is missing or
        # unusable, so a caller falls back to its own backoff instead of retrying at once.
        def retry_after(headers)
          _, value = headers.find { |name, _| name.to_s.casecmp?("retry-after") }
          value = value.first if value.is_a?(Array)
          value = value.to_s.strip
          return if value.empty?
          return value.to_i if value.match?(/\A\d+\z/)

          [(Time.httpdate(value) - Time.now).ceil, 0].max
        rescue ArgumentError
          nil
        end

        def instrument(name, payload, &block)
          return yield(payload) unless @instrumenter

          @instrumenter.instrument(name, payload, &block)
        end

        def call_transport(uri, headers, json)
          @transport.call(uri, headers, json)
        rescue *NETWORK_ERRORS => e
          [nil, "#{e.class}: #{e.message}"]
        end

        def http_post(uri, headers, json)
          request = Net::HTTP::Post.new(uri, headers)
          request.body = json
          response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: @timeout,
                                     read_timeout: @timeout, write_timeout: @timeout) do |http|
            http.request(request)
          end
          [response.code.to_i, response.body, response.to_hash]
        end

        def parse(body)
          JSON.parse(body.to_s)
        rescue JSON::ParserError
          nil
        end
    end
  end
end
