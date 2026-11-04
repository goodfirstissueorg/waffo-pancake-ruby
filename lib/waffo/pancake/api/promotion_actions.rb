# frozen_string_literal: true

module Waffo
  module Pancake
    module API
      # Coupons, promotion codes and the prompt scan. Merchant API key.
      module PromotionActions
        # discount: { type: "percentage", percentOff: 20 }
        def create_coupon(store_id:, name:, discount:, **params)
          action("/v1/actions/coupon/create-coupon", store_id: store_id, name: name, discount: discount, **params)
        end

        def update_coupon(id:, name:, **params)
          action("/v1/actions/coupon/update-coupon", id: id, name: name, **params)
        end

        def deactivate_coupon(id:, **params)
          action("/v1/actions/coupon/deactivate-coupon", id: id, **params)
        end

        def create_promotion_code(coupon_id:, **params)
          action("/v1/actions/promotion-code/create-promotion-code", coupon_id: coupon_id, **params)
        end

        def generate_promotion_codes(coupon_id:, count:, **params)
          action("/v1/actions/promotion-code/generate-promotion-codes", coupon_id: coupon_id, count: count, **params)
        end

        def deactivate_promotion_code(id:, **params)
          action("/v1/actions/promotion-code/deactivate-promotion-code", id: id, **params)
        end

        def scan_prompt(prompt:, **params)
          action("/v1/actions/verification/scan-prompt", prompt: prompt, **params)
        end
      end
    end
  end
end
