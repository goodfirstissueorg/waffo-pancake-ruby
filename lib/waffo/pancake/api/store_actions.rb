# frozen_string_literal: true

module Waffo
  module Pancake
    module API
      # Stores, their members, webhook endpoints and notification recipients. Merchant API key.
      module StoreActions
        def create_store(name:, **params)
          action("/v1/actions/store/create-store", name: name, **params)
        end

        # Omitted keeps a field, Waffo::Pancake::NULL clears it, a value sets it.
        def update_store(id:, **params)
          action("/v1/actions/store/update-store", id: id, **params)
        end

        def delete_store(id:, **params)
          action("/v1/actions/store/delete-store", id: id, **params)
        end

        def add_store_merchant(store_id:, email:, role:, **params)
          action("/v1/actions/store-merchant/add-merchant", store_id: store_id, email: email, role: role, **params)
        end

        def remove_store_merchant(store_id:, merchant_id:, **params)
          action("/v1/actions/store-merchant/remove-merchant", store_id: store_id, merchant_id: merchant_id, **params)
        end

        def update_store_merchant_role(store_id:, merchant_id:, role:, **params)
          action("/v1/actions/store-merchant/update-role", store_id: store_id, merchant_id: merchant_id, role: role,
                                                           **params)
        end

        def add_webhook(store_id:, url:, events:, test_mode:, channel: "http", **params)
          action("/v1/actions/store/add-webhook", store_id: store_id, channel: channel, url: url, events: events,
                                                  test_mode: test_mode, **params)
        end

        # `secret: Waffo::Pancake::NULL` clears the secret.
        def update_webhook(id:, **params)
          action("/v1/actions/store/update-webhook", id: id, **params)
        end

        def remove_webhook(id:, **params)
          action("/v1/actions/store/remove-webhook", id: id, **params)
        end

        def add_notification_recipient(store_id:, email:, **params)
          action("/v1/actions/store-notification-recipient/add-recipient", store_id: store_id, email: email, **params)
        end

        def update_notification_recipient(store_id:, recipient_id:, preferences:, **params)
          action("/v1/actions/store-notification-recipient/update-recipient",
                 store_id: store_id, recipient_id: recipient_id, preferences: preferences, **params)
        end

        def remove_notification_recipient(store_id:, recipient_id:, **params)
          action("/v1/actions/store-notification-recipient/remove-recipient",
                 store_id: store_id, recipient_id: recipient_id, **params)
        end
      end
    end
  end
end
