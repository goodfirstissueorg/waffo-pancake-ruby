# frozen_string_literal: true

require "openssl"

module Waffo
  module Pancake
    # Turns the shapes keys arrive in (PEM, PEM with literal "\n" from an env file, CRLF,
    # a one-line body, bare base64) into OpenSSL keys, as @waffo/pancake-ts does.
    module Keys
      module_function

      def private_key(raw)
        return raw if raw.is_a?(OpenSSL::PKey::RSA)

        pem = clean(raw, "private")
        kind = pem.include?("BEGIN RSA PRIVATE KEY") ? "RSA PRIVATE KEY" : "PRIVATE KEY"
        OpenSSL::PKey::RSA.new(wrap(body_of(pem, "PRIVATE"), kind))
      rescue OpenSSL::PKey::PKeyError, ArgumentError
        raise ConfigurationError, "The private key is not a valid RSA private key (PKCS#8 or PKCS#1)"
      end

      def public_key(raw)
        return raw if raw.is_a?(OpenSSL::PKey::RSA)

        pem = clean(raw, "public")
        kind = pem.include?("BEGIN RSA PUBLIC KEY") ? "RSA PUBLIC KEY" : "PUBLIC KEY"
        OpenSSL::PKey::RSA.new(wrap(body_of(pem, "PUBLIC"), kind))
      rescue OpenSSL::PKey::PKeyError, ArgumentError
        raise ConfigurationError, "The public key is not a valid RSA public key (SPKI or PKCS#1)"
      end

      def clean(raw, label)
        pem = raw.to_s.gsub("\\n", "\n").gsub("\r\n", "\n").strip
        raise ConfigurationError, "The #{label} key is empty" if pem.empty?

        pem
      end

      def body_of(pem, label)
        body = pem.gsub(/-----(BEGIN|END) (RSA )?#{label} KEY-----/, "").gsub(/\s+/, "")
        raise ArgumentError, "no key data" unless body.match?(%r{\A[A-Za-z0-9+/]+=*\z})

        body
      end

      def wrap(body, kind)
        "-----BEGIN #{kind}-----\n#{body.scan(/.{1,64}/).join("\n")}\n-----END #{kind}-----\n"
      end
    end
  end
end
