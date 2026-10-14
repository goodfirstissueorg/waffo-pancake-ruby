# frozen_string_literal: true

require_relative "rails_helper"

class CustomerPortalControllerTest < Minitest::Test
  include Waffo::Pancake::TestHelpers

  def visit(path = "/portal") = Rack::MockRequest.new(Rails.application).get(path)

  def test_redirects_to_a_fresh_portal_link_without_caching_or_a_referrer
    with_fake_waffo_client do |client|
      response = visit("/portal?buyer_identity=someone-else")

      assert_equal 302, response.status
      assert_equal "https://pancake.waffo.ai/consumer/portal/store/STO_test#token=test_token", response.location
      assert_equal "no-store", response.headers["Cache-Control"]
      assert_equal "no-referrer", response.headers["Referrer-Policy"]
      assert_equal [:create_customer_portal_link, { buyer_identity: "user-from-session", store_id: "STO_from_config" }],
                   client.calls.last, "the identity comes from the session, not the request"
    end
  end

  def test_the_portal_url_stays_out_of_the_request_log
    log = StringIO.new
    previous = ActionController::Base.logger
    ActionController::Base.logger = Logger.new(log)

    with_fake_waffo_client { visit }

    assert_includes log.string, "Redirected to [FILTERED]"
    refute_includes log.string, "test_token"
  ensure
    ActionController::Base.logger = previous
  end

  def test_a_failed_link_is_a_bad_gateway
    client = FakeClient.new
    client.fail_with = Waffo::Pancake::Unavailable.new("Waffo /v1/actions/auth/issue-session-token status=503: down")

    with_fake_waffo_client(client) do
      response = visit

      assert_equal 502, response.status
      assert_nil response.location
      assert_equal "no-store", response.headers["Cache-Control"]
    end
  end
end
