# frozen_string_literal: true

require_relative "rails_helper"

class RailtieTest < Minitest::Test
  def config = Waffo::Pancake.configuration

  def test_credentials_then_application_config_override_the_environment
    assert_equal "MER_from_credentials", config.merchant_id
    assert_equal "test", config.environment
    assert_equal "STO_from_config", config.store_id, "config.waffo_pancake wins over credentials"
    assert_equal 7, config.timeout
  end

  def test_logs_to_rails_and_reports_to_active_support_notifications
    assert_same Rails.logger, config.logger
    assert_same ActiveSupport::Notifications, config.instrumenter
  end

  def test_filters_the_private_key_from_logs
    assert_includes Rails.application.config.filter_parameters, :private_key
  end

  def test_shared_client_is_built_from_it
    assert_equal "MER_from_credentials", Waffo::Pancake.client.merchant_id
  end

  def test_request_events_reach_subscribers
    events = []
    subscriber = ActiveSupport::Notifications.subscribe("request.waffo_pancake") { |event| events << event.payload }
    transport = ->(*) { [503, "down"] }
    client = Waffo::Pancake::Client.new(transport: transport)

    assert_raises(Waffo::Pancake::Unavailable) { client.cancel_subscription("ORD_1") }
    assert_equal({ method: "POST", path: "/v1/actions/subscription-order/cancel-order", status: 503 }, events.last)
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end
end
