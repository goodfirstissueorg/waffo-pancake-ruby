# frozen_string_literal: true

require "active_support/concern"

module Waffo
  module Pancake
    # Include in the controller that receives Waffo's webhooks:
    #
    #   class WaffoWebhooksController < ActionController::Base
    #     include Waffo::Pancake::WebhookController
    #
    #     def create
    #       HandleWaffoEventJob.perform_later(waffo_event)  # already verified
    #       head :ok
    #     end
    #   end
    #
    # Before the action it reads the raw body, verifies X-Waffo-Signature with
    # Waffo::Pancake.verify_webhook and exposes the event as `waffo_event`. A bad signature is
    # answered 401 and an oversized body 413, without reaching the action. A delivery for
    # another environment or store (when `environment` / `store_id` are configured) is
    # acknowledged with 200 and skipped, since an error status only makes Waffo retry it.
    #
    # Deduplicate on `waffo_event["id"]`: a retry redelivers the same id.
    module WebhookController
      extend ActiveSupport::Concern

      MAX_BODY_BYTES = 256 * 1024

      included do
        skip_forgery_protection if respond_to?(:skip_forgery_protection)
        wrap_parameters false if respond_to?(:wrap_parameters)
        before_action :verify_waffo_webhook!
      end

      # The body is trusted only once its signature checks out. Left to Rails it would be
      # parsed into params first and written whole into the request log.
      def process_action(...)
        request.delete_header("action_dispatch.request.parameters")
        request.request_parameters = {}
        super
      end

      private
        attr_reader :waffo_event

        def verify_waffo_webhook!
          body = request.body.read(MAX_BODY_BYTES + 1).to_s
          request.body.rewind if request.body.respond_to?(:rewind)
          return head(413) if body.bytesize > MAX_BODY_BYTES

          @waffo_event = Waffo::Pancake.verify_webhook(body, request.headers[Webhook::SIGNATURE_HEADER])
          return head(:bad_request) unless @waffo_event.is_a?(Hash) && @waffo_event["id"]
          return if waffo_event_for_this_account?

          waffo_webhook_log(:info, "skipped event=#{@waffo_event["id"]} mode=#{@waffo_event["mode"]} " \
                                   "store=#{@waffo_event["storeId"]}: not this environment or store")
          head :ok
        rescue Waffo::Pancake::InvalidSignature => e
          waffo_webhook_log(:warn, "refused: #{e.message}")
          head :unauthorized
        end

        def waffo_event_for_this_account?
          config = Waffo::Pancake.configuration
          return false if config.environment && waffo_event["mode"] != config.environment

          config.store_id.to_s.strip.empty? || waffo_event["storeId"] == config.store_id
        end

        def waffo_webhook_log(level, message)
          (Waffo::Pancake.configuration.logger || logger)&.public_send(level, "[Waffo] webhook #{message}")
        end
    end
  end
end
