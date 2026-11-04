# frozen_string_literal: true

module Waffo
  module Pancake
    module API
      # Products and subscription product groups. Merchant API key.
      module ProductActions
        # prices: { "USD" => { amount: "9.99", taxCategory: "saas" } }
        def create_subscription_product(store_id:, name:, billing_period:, prices:, **params)
          action("/v1/actions/subscription-product/create-product",
                 store_id: store_id, name: name, billing_period: billing_period, prices: prices, **params)
        end

        def update_subscription_product(id:, **params)
          action("/v1/actions/subscription-product/update-product", id: id, **params)
        end

        # Copies the test version to production (first publish only).
        def publish_subscription_product(id:, **params)
          action("/v1/actions/subscription-product/publish-product", id: id, **params)
        end

        # status: "active" or "inactive"
        def update_subscription_product_status(id:, status:, **params)
          action("/v1/actions/subscription-product/update-status", id: id, status: status, **params)
        end

        def create_onetime_product(store_id:, name:, prices:, **params)
          action("/v1/actions/onetime-product/create-product", store_id: store_id, name: name, prices: prices, **params)
        end

        def update_onetime_product(id:, **params)
          action("/v1/actions/onetime-product/update-product", id: id, **params)
        end

        # Copies the test version to production.
        def publish_onetime_product(id:, **params)
          action("/v1/actions/onetime-product/publish-product", id: id, **params)
        end

        # status: "active" or "inactive"
        def update_onetime_product_status(id:, status:, **params)
          action("/v1/actions/onetime-product/update-status", id: id, status: status, **params)
        end

        def create_subscription_product_group(store_id:, name:, **params)
          action("/v1/actions/subscription-product-group/create-group", store_id: store_id, name: name, **params)
        end

        def update_subscription_product_group(id:, **params)
          action("/v1/actions/subscription-product-group/update-group", id: id, **params)
        end

        def delete_subscription_product_group(id:, **params)
          action("/v1/actions/subscription-product-group/delete-group", id: id, **params)
        end

        def publish_subscription_product_group(id:, **params)
          action("/v1/actions/subscription-product-group/publish-group", id: id, **params)
        end
      end
    end
  end
end
