# frozen_string_literal: true

require "active_support/concern"

module Waffo
  module Pancake
    # Sends a customer who is signed in on your site into the store's Waffo customer portal,
    # with no email code:
    #
    #   class WaffoPortalController < ApplicationController
    #     include Waffo::Pancake::CustomerPortalController
    #     before_action :authenticate_user!            # your own sign-in
    #
    #     def show
    #       redirect_to_waffo_customer_portal(buyer_identity: current_user.id)
    #     end
    #   end
    #
    # Link to the route with a plain link (a prefetch would make links nobody clicked). Each
    # request gets a new portal link, answered with a 302, `Cache-Control: no-store` and
    # `Referrer-Policy: no-referrer`; the Railtie keeps the URL out of the request log. When
    # Waffo cannot make a link, the answer is a 502 and the error is logged without the URL.
    module CustomerPortalController
      extend ActiveSupport::Concern

      NO_STORE_HEADERS = { "Cache-Control" => "no-store", "Referrer-Policy" => "no-referrer" }.freeze

      private
        # `buyer_identity` is the one given at authenticated checkout and must come from your
        # session, never from params. `store_id` defaults to the configured store.
        def redirect_to_waffo_customer_portal(buyer_identity:, store_id: nil, client: nil)
          response.headers.merge!(NO_STORE_HEADERS)
          store_id ||= Waffo::Pancake.configuration.store_id
          link = (client || Waffo::Pancake.client).create_customer_portal_link(buyer_identity: buyer_identity,
                                                                               store_id: store_id)
          redirect_to link.fetch("portalUrl"), allow_other_host: true, status: :found
        rescue Waffo::Pancake::Error => e
          (Waffo::Pancake.configuration.logger || logger)&.error("[Waffo] customer portal link failed: #{e.message}")
          head :bad_gateway
        end
    end
  end
end
