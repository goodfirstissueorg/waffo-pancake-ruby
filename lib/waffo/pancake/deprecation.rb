# frozen_string_literal: true

require "set"

module Waffo
  module Pancake
    # Reports the use of fields Waffo has deprecated. The reporter is `configuration.deprecator`:
    # anything answering `warn(message, callstack)`, such as ActiveSupport::Deprecation (the
    # Railtie sets one up) or the Warner below, the default outside Rails. Set it to nil to stay
    # silent.
    module Deprecation
      # Writes each distinct message once per process to $stderr through Kernel#warn, with the
      # line that read the field.
      class Warner
        def initialize
          @seen = Set.new
          @mutex = Mutex.new
        end

        def warn(message, callstack = nil)
          return unless @mutex.synchronize { @seen.add?(message) }

          location = Array(callstack).first
          Kernel.warn("DEPRECATION WARNING: #{message}#{" (called from #{location})" if location} [waffo-pancake]")
        end
      end

      @default = Warner.new

      class << self
        # The Warner shared by the process, so a message is not repeated per configuration.
        attr_reader :default

        def warn(message, callstack = caller_locations(1))
          Pancake.configuration.deprecator&.warn(message, callstack)
        end
      end
    end
  end
end
