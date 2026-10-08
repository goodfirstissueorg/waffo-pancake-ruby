# frozen_string_literal: true

require_relative "pancake/version"
require_relative "pancake/errors"
require_relative "pancake/keys"
require_relative "pancake/client"
require_relative "pancake/webhook"
require_relative "pancake/configuration"
require_relative "pancake/railtie" if defined?(Rails::Railtie)

module Waffo
  # Ruby client for the Waffo Pancake merchant API (https://docs.waffo.ai).
  module Pancake
    # Need ActiveSupport / Action Pack; loaded on first use.
    autoload :WebhookController, "waffo/pancake/webhook_controller"
    autoload :TestHelpers, "waffo/pancake/test_helpers"
  end
end
