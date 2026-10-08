# frozen_string_literal: true

require "test_helper"

class KeysTest < Minitest::Test
  KEY = TestKeys::KEY

  def test_private_key_shapes
    der = Base64.strict_encode64(KEY.private_to_der)
    one_line = "-----BEGIN PRIVATE KEY-----#{der}-----END PRIVATE KEY-----"

    [KEY.private_to_pem, KEY.private_to_pem.gsub("\n", "\\n"), KEY.private_to_pem.gsub("\n", "\r\n"), der, one_line,
     KEY.to_pem].each do |shape|
      assert_equal KEY.to_der, Waffo::Pancake::Keys.private_key(shape).to_der
    end
  end

  def test_public_key_shapes
    der = Base64.strict_encode64(KEY.public_to_der)

    [KEY.public_to_pem, KEY.public_to_pem.gsub("\n", "\\n"), der].each do |shape|
      assert_equal KEY.public_to_der, Waffo::Pancake::Keys.public_key(shape).public_to_der
    end
  end

  def test_rejects_garbage
    assert_raises(Waffo::Pancake::ConfigurationError) { Waffo::Pancake::Keys.private_key("") }
    assert_raises(Waffo::Pancake::ConfigurationError) { Waffo::Pancake::Keys.private_key("not base64!") }
    assert_raises(Waffo::Pancake::ConfigurationError) { Waffo::Pancake::Keys.public_key("QUJD") }
  end
end
