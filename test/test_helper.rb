# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "waffo/pancake"
require "minitest/autorun"

module TestKeys
  KEY = OpenSSL::PKey::RSA.generate(2048)

  module_function

  def webhook_header(body, at: Time.now, key: KEY)
    timestamp = (at.to_f * 1000).to_i
    "t=#{timestamp},v1=#{Base64.strict_encode64(key.sign(OpenSSL::Digest::SHA256.new, "#{timestamp}.#{body}"))}"
  end
end
