#!/usr/bin/env ruby
# asc_build_number.rb — prints the next CFBundleVersion for a marketing
# version, computed from what App Store Connect already has for that exact
# version: last existing build + 1, or 1 if none exist yet.
#
# This is what lets a fresh release/X.Y.Z branch start at build 1 and every
# later push to the same branch produce build 2, 3, ... with nothing tracked
# by hand. Ruby stdlib only (openssl, json, net/http) — no gems to install
# on Xcode Cloud's Mac.
#
# Usage: ruby scripts/ci/asc_build_number.rb <marketing_version> <bundle_id>
# Requires env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_CONTENT
#   (Xcode Cloud → workflow → Environment — separate store from GitHub Secrets)

require "openssl"
require "base64"
require "json"
require "net/http"
require "uri"
require "time"

def b64url(bytes)
  Base64.urlsafe_encode64(bytes, padding: false)
end

def int_to_bytes(int, length)
  [int.to_s(16).rjust(length * 2, "0")].pack("H*")
end

# Secret stores vary in how they hand back a pasted multi-line PEM key:
# real newlines, literal "\n" escapes, the BEGIN/END markers stripped
# entirely (just the base64 body pasted), or the whole thing flattened
# onto one line once those markers lose their surrounding newlines.
# Handle all of these rather than depend on the paste going in perfectly.
def normalize_pem(key_pem)
  key_pem = key_pem.strip
  key_pem = key_pem.gsub('\\n', "\n") if key_pem.include?('\\n') && !key_pem.include?("\n")

  unless key_pem.include?("BEGIN")
    return "-----BEGIN PRIVATE KEY-----\n#{key_pem}\n-----END PRIVATE KEY-----" # gitleaks:allow — marker string, not a real key
  end

  return key_pem if key_pem.include?("\n")

  key_pem
    .sub(/-----BEGIN PRIVATE KEY-----\s*/, "-----BEGIN PRIVATE KEY-----\n") # gitleaks:allow — marker string, not a real key
    .sub(/\s*-----END PRIVATE KEY-----/, "\n-----END PRIVATE KEY-----")
end

# App Store Connect API JWT: ES256, signed with the .p8 key. OpenSSL's
# EC#sign returns a DER-encoded (r, s) sequence; JWS needs the raw 32-byte
# r || s concatenation instead, so it's decoded and repacked by hand.
def mint_jwt(key_id, issuer_id, key_pem)
  header = { alg: "ES256", kid: key_id, typ: "JWT" }
  now = Time.now.to_i
  payload = { iss: issuer_id, iat: now, exp: now + 600, aud: "appstoreconnect-v1" }

  signing_input = "#{b64url(header.to_json)}.#{b64url(payload.to_json)}"

  key = OpenSSL::PKey.read(normalize_pem(key_pem))
  der_signature = key.sign(OpenSSL::Digest.new("SHA256"), signing_input)

  r, s = OpenSSL::ASN1.decode(der_signature).value.map { |v| v.value.to_i }
  raw_signature = int_to_bytes(r, 32) + int_to_bytes(s, 32)

  "#{signing_input}.#{b64url(raw_signature)}"
end

def asc_get(path, token)
  uri = URI("https://api.appstoreconnect.apple.com#{path}")
  request = Net::HTTP::Get.new(uri)
  request["Authorization"] = "Bearer #{token}"

  # Xcode Cloud's runners hit transient SSL resets / timeouts talking to the
  # ASC API, and a single blip must not fail the whole archive. Retry network
  # errors and transient server responses (429/5xx) with exponential backoff.
  attempts = 0
  begin
    attempts += 1
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                               open_timeout: 20, read_timeout: 30) { |http| http.request(request) }
    if (response.is_a?(Net::HTTPTooManyRequests) || response.is_a?(Net::HTTPServerError)) && attempts < 5
      raise IOError, "transient HTTP #{response.code}"
    end
  rescue Errno::ECONNRESET, Errno::ETIMEDOUT, Errno::ECONNREFUSED, EOFError, IOError,
         Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError, SocketError => e
    if attempts < 5
      sleep(2**attempts) # 2, 4, 8, 16s
      retry
    end
    abort "App Store Connect API unreachable after #{attempts} attempts for #{path}: #{e.class}: #{e.message}"
  end

  unless response.is_a?(Net::HTTPSuccess)
    abort "App Store Connect API error #{response.code} for #{path}: #{response.body}"
  end

  JSON.parse(response.body)
end

def env_or_abort(name)
  ENV.fetch(name) { abort "#{name} not set — add it as an Xcode Cloud Environment Variable" }
end

version    = ARGV[0] or abort "usage: scripts/ci/asc_build_number.rb <version> <bundle_id>"
bundle_id  = ARGV[1] or abort "usage: scripts/ci/asc_build_number.rb <version> <bundle_id>"

key_id     = env_or_abort("ASC_KEY_ID")
issuer_id  = env_or_abort("ASC_ISSUER_ID")
key_pem    = env_or_abort("ASC_KEY_CONTENT")

token = mint_jwt(key_id, issuer_id, key_pem)

apps = asc_get("/v1/apps?filter[bundleId]=#{bundle_id}", token)
app_id = apps["data"]&.first&.fetch("id", nil)
abort "no App Store Connect app found for bundle id #{bundle_id}" unless app_id

builds_path = "/v1/builds?filter[app]=#{app_id}&filter[preReleaseVersion.version]=#{version}" \
              "&sort=-version&limit=1&fields[builds]=version"
builds = asc_get(builds_path, token)
last_build = builds["data"]&.first&.dig("attributes", "version")

next_build = last_build ? last_build.to_i + 1 : 1
puts next_build
