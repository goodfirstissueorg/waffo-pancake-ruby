# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)

require "logger"
require "rails"
require "action_controller/railtie"
require "active_record"
require "waffo/pancake"
require "waffo/pancake/test_helpers"
require "minitest/autorun"

module RailsTest
  KEY = Waffo::Pancake::TestHelpers.key

  class Application < Rails::Application
    config.root = File.expand_path("app", __dir__)
    config.eager_load = false
    config.logger = Logger.new(nil)
    config.secret_key_base = "x" * 64
    config.hosts.clear
    config.waffo_pancake.store_id = "STO_from_config"
    config.waffo_pancake.timeout = 7

    # Stands in for config/credentials.yml.enc.
    def credentials
      @credentials ||= ActiveSupport::OrderedOptions.new.tap do |credentials|
        credentials[:waffo] = {
          merchant_id: "MER_from_credentials", private_key: KEY.private_to_pem,
          store_id: "STO_from_credentials", environment: "test"
        }
      end
    end
  end
end

ENV.delete("WAFFO_MERCHANT_ID")
ENV.delete("WAFFO_STORE_ID")
RailsTest::Application.initialize!

RailsTest::Application.routes.draw do
  post "webhooks/waffo", to: "waffo_webhooks#create"
end

class WaffoWebhooksController < ActionController::Base
  include Waffo::Pancake::WebhookController

  def create
    render json: { id: waffo_event["id"], type: waffo_event["eventType"], params: params.to_unsafe_h.keys.sort }
  end
end
