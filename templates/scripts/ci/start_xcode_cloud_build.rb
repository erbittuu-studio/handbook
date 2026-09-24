#!/usr/bin/env ruby
# frozen_string_literal: true

# Starts an Xcode Cloud build, on purpose.
#
# Xcode Cloud's own start conditions are set to Manual, so it never builds by
# itself — GitHub decides instead, since the paths filter in main.yml already
# knows exactly what a push contained. Preferred over a Files and Folders rule
# on Apple's side, since Apple doesn't document what happens when one commit
# touches both an excluded folder and a source file.
#
#   ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_CONTENT   App Store Connect API key
#
#   ruby start_xcode_cloud_build.rb <workflow name> <branch>   start a build
#
# Defaults to this app's product; --product <name> picks another.
#   ruby start_xcode_cloud_build.rb --list                     show what exists
#
# JWT/HTTP helpers are duplicated from App/ci_scripts/lib/asc_build_number.rb
# deliberately — that script runs inside every archive and decides the build
# number, and breaking it to save lines here would be a poor trade.

require "base64"
require "json"
require "net/http"
require "openssl"
require "uri"

def b64url(data)
  Base64.urlsafe_encode64(data).delete("=")
end

def int_to_bytes(value, length)
  [value.to_s(16).rjust(length * 2, "0")].pack("H*")
end

def normalize_pem(key_pem)
  return key_pem if key_pem.include?("\n")

  key_pem
    .sub(/-----BEGIN PRIVATE KEY-----\s*/, "-----BEGIN PRIVATE KEY-----\n") # gitleaks:allow — marker string
    .sub(/\s*-----END PRIVATE KEY-----/, "\n-----END PRIVATE KEY-----")     # gitleaks:allow — marker string
end

def mint_jwt(key_id, issuer_id, key_pem)
  header = { alg: "ES256", kid: key_id, typ: "JWT" }
  now = Time.now.to_i
  payload = { iss: issuer_id, iat: now, exp: now + 600, aud: "appstoreconnect-v1" }
  signing_input = "#{b64url(header.to_json)}.#{b64url(payload.to_json)}"

  key = OpenSSL::PKey.read(normalize_pem(key_pem))
  der = key.sign(OpenSSL::Digest.new("SHA256"), signing_input)
  r, s = OpenSSL::ASN1.decode(der).value.map { |v| v.value.to_i }

  "#{signing_input}.#{b64url(int_to_bytes(r, 32) + int_to_bytes(s, 32))}"
end

# Retries the blips, not the refusals. A dropped connection or a 429 must not
# cost a TestFlight build; a 400 means the request is wrong and retrying it just
# makes the same mistake five times.
def asc(method, path, token, body = nil)
  uri = URI("https://api.appstoreconnect.apple.com#{path}")
  attempts = 0

  begin
    attempts += 1
    request = method == :post ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{token}"
    if body
      request["Content-Type"] = "application/json"
      request.body = body.to_json
    end

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
    abort "App Store Connect API #{response.code} for #{method.upcase} #{path}\n#{response.body}"
  end

  response.body.to_s.empty? ? {} : JSON.parse(response.body)
end

def env_or_abort(name)
  ENV.fetch(name) { abort "#{name} not set" }
end

token = mint_jwt(env_or_abort("ASC_KEY_ID"),
                 env_or_abort("ASC_ISSUER_ID"),
                 env_or_abort("ASC_KEY_CONTENT"))

# One API key sees every app in the account — seven of them here — so the
# product has to be named. Taking the first one would have started a build for
# a different app entirely.
product_name = ARGV.index("--product")&.then { |i| ARGV[i + 1] } || "{{APP_NAME}}"

products = asc(:get, "/v1/ciProducts?limit=200", token)["data"] || []
abort "no Xcode Cloud products visible to this API key" if products.empty?

product = products.find { |candidate| candidate.dig("attributes", "name") == product_name }
unless product
  available = products.map { |candidate| candidate.dig("attributes", "name") }.sort.join(", ")
  abort "no Xcode Cloud product named '#{product_name}'. Available: #{available}"
end

workflows = asc(:get, "/v1/ciProducts/#{product['id']}/workflows?limit=200", token)["data"] || []

if ARGV.include?("--list")
  puts "product: #{product.dig('attributes', 'name')} (#{product['id']})"
  workflows.each do |workflow|
    attributes = workflow["attributes"] || {}
    puts "  workflow: #{attributes['name']} (#{workflow['id']})  enabled=#{attributes['isEnabled']}"
  end
  exit 0
end

workflow_name = ARGV[0] or abort "usage: start_xcode_cloud_build.rb <workflow name> <branch>"
branch        = ARGV[1] or abort "usage: start_xcode_cloud_build.rb <workflow name> <branch>"

workflow = workflows.find { |w| w.dig("attributes", "name") == workflow_name }
unless workflow
  available = workflows.map { |w| w.dig("attributes", "name") }.join(", ")
  abort "no Xcode Cloud workflow named '#{workflow_name}'. Available: #{available}"
end

# A build has to be pointed at a branch, and Apple identifies one by an opaque
# git-reference id rather than by name, so it has to be looked up.
repositories = asc(:get, "/v1/ciProducts/#{product['id']}/primaryRepositories?limit=200", token)["data"] || []
abort "no repository attached to the Xcode Cloud product" if repositories.empty?

references = asc(:get, "/v1/scmRepositories/#{repositories.first['id']}/gitReferences?limit=200", token)["data"] || []
reference = references.find do |ref|
  ref.dig("attributes", "kind") == "BRANCH" && ref.dig("attributes", "name") == branch
end
unless reference
  abort "Xcode Cloud has not seen a branch called '#{branch}' yet. " \
        "Push it once, or check the name."
end

created = asc(:post, "/v1/ciBuildRuns", token, {
                "data" => {
                  "type" => "ciBuildRuns",
                  "attributes" => {},
                  "relationships" => {
                    "workflow" => { "data" => { "type" => "ciWorkflows", "id" => workflow["id"] } },
                    "sourceBranchOrTag" => { "data" => { "type" => "scmGitReferences", "id" => reference["id"] } }
                  }
                }
              })

number = created.dig("data", "attributes", "number")
puts "Started '#{workflow_name}' on #{branch} — build #{number || created.dig('data', 'id')}"
