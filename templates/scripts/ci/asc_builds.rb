#!/usr/bin/env ruby
# frozen_string_literal: true

# Read-only. Prints why App Store Connect will or will not let a build be
# attached to a version.
#
#   ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_CONTENT   App Store Connect API key
#   ruby scripts/ci/asc_builds.rb
#
# The "Add Build" dialog lists builds and silently refuses to select some,
# with no reason given. Every reason it could have is a field the API
# returns plainly:
#
#   processingState      only VALID can be attached.
#   usesNonExemptEncryption
#                        null is "Missing Compliance" — the most common
#                        cause. Apple sets it from ITSAppUsesNonExemptEncryption
#                        in the archive's Info.plist; when absent it has to
#                        be answered by hand, per build, in TestFlight.
#   expired              TestFlight builds expire 90 days after upload and
#                        stay in the list, unselectable.
#   buildAudienceType    INTERNAL_ONLY can NEVER be attached to an App Store
#                        version — set by the Xcode Cloud workflow's archive
#                        post-action, so every build that workflow makes has
#                        it until the workflow changes.
#
# So this also reads the Xcode Cloud workflow, since the build field is the
# symptom and the workflow field is the cause.
#
# JWT/HTTP helpers are duplicated from xcode_cloud_workflow.rb so each script
# stays readable on its own.

require "base64"
require "json"
require "net/http"
require "openssl"
require "time"
require "uri"

def b64url(data) = Base64.urlsafe_encode64(data).delete("=")
def int_to_bytes(value, length) = [value.to_s(16).rjust(length * 2, "0")].pack("H*")

# Turn whatever ASC_KEY_CONTENT actually holds into PEM OpenSSL will read.
# Handles three real shapes: newlines escaped as literal backslash-n (a
# secret pasted through a shell or JSON field), the whole .p8 stored
# base64-encoded with no markers at all, and a single-line body needing
# 64-character wrapping.
def normalize_pem(key_pem)
  key = key_pem.to_s.strip
  key = key.gsub('\n', "\n") if key.include?('\n')

  unless key.include?("-----BEGIN") # gitleaks:allow — marker string
    decoded = begin
      Base64.decode64(key)
    rescue StandardError
      ""
    end
    key = decoded if decoded.include?("-----BEGIN") # gitleaks:allow — marker string
  end

  # Already properly wrapped: markers plus a body on their own lines.
  return key if key.lines.count { |l| !l.strip.empty? } > 2

  body = key.sub(/\A.*?-----BEGIN [A-Z ]*PRIVATE KEY-----/m, "") # gitleaks:allow — marker string
            .sub(/-----END [A-Z ]*PRIVATE KEY-----.*\z/m, "")    # gitleaks:allow — marker string
            .gsub(/\s+/, "")
  return key if body.empty?

  ["-----BEGIN PRIVATE KEY-----",                                # gitleaks:allow — marker string
   body.scan(/.{1,64}/),
   "-----END PRIVATE KEY-----"].flatten.join("\n") + "\n"       # gitleaks:allow — marker string
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

def asc(path, token)
  uri = URI("https://api.appstoreconnect.apple.com#{path}")
  request = Net::HTTP::Get.new(uri)
  request["Authorization"] = "Bearer #{token}"
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                             open_timeout: 20, read_timeout: 30) { |http| http.request(request) }
  unless response.is_a?(Net::HTTPSuccess)
    abort "App Store Connect API #{response.code} for GET #{path}\n#{response.body}"
  end

  JSON.parse(response.body)
end

def env_or_abort(name) = ENV.fetch(name) { abort "#{name} not set" }

root = File.expand_path("../..", __dir__)
project = if File.exist?(File.join(root, "project.yml"))
            require "yaml"
            YAML.safe_load(File.read(File.join(root, "project.yml")), aliases: true)
          else
            JSON.parse(File.read(File.join(root, "Project.json")))
          end
bundle_id = project.dig("app", "bundleId")

token = mint_jwt(env_or_abort("ASC_KEY_ID"),
                 env_or_abort("ASC_ISSUER_ID"),
                 env_or_abort("ASC_KEY_CONTENT"))

app = asc("/v1/apps?filter[bundleId]=#{bundle_id}", token)["data"].first
abort "no app with bundle id #{bundle_id}" unless app
puts "App: #{app.dig('attributes', 'name')}  (#{bundle_id})  id=#{app['id']}"

# Versions, so we can say which one the build would attach to.
versions = asc("/v1/apps/#{app['id']}/appStoreVersions?limit=5", token)["data"]
puts "\nVersions"
versions.each do |v|
  a = v["attributes"]
  puts format("  %-8s %-28s platform=%s", a["versionString"], a["appStoreState"], a["platform"])
end

build_fields = %w[version processingState expired usesNonExemptEncryption
                  buildAudienceType uploadedDate].join(",")
builds = asc("/v1/builds?filter[app]=#{app['id']}&limit=20&sort=-version" \
             "&fields[builds]=#{build_fields}", token)["data"]
puts "\nBuilds (newest first)"
puts format("  %-6s %-12s %-8s %-18s %-20s %s",
            "BUILD", "PROCESSING", "EXPIRED", "ENCRYPTION", "AUDIENCE", "ATTACHABLE?")

blocked = []
builds.each do |b|
  a = b["attributes"]
  state    = a["processingState"]
  expired  = a["expired"]
  crypto   = a["usesNonExemptEncryption"]
  crypto_s = crypto.nil? ? "MISSING (null)" : crypto.to_s

  audience = a["buildAudienceType"] || "(not reported)"

  reasons = []
  reasons << "processingState=#{state}" unless state == "VALID"
  reasons << "expired" if expired
  reasons << "missing export compliance" if crypto.nil?
  reasons << "INTERNAL_ONLY — not App Store eligible" if audience == "INTERNAL_ONLY"
  ok = reasons.empty?

  blocked << [a["version"], reasons] unless ok
  puts format("  %-6s %-12s %-8s %-18s %-20s %s",
              a["version"], state, expired.to_s, crypto_s, audience,
              ok ? "yes" : "NO — #{reasons.join(', ')}")
end

# The workflow that made them. `buildAudienceType` says what a build IS;
# `buildDistributionAudience` on the archive action says what the workflow will
# keep producing, which is the thing that actually has to change.
puts "\nXcode Cloud workflows"
begin
  products = asc("/v1/ciProducts?limit=10", token)["data"]
  product = products.find { |p| p.dig("attributes", "name")&.include?("{{APP_NAME}}") } || products.first
  if product
    workflows = asc("/v1/ciProducts/#{product['id']}/workflows?limit=20", token)["data"]
    workflows.each do |w|
      wa = w["attributes"]
      actions = (wa["actions"] || []).map do |act|
        next unless act["actionType"] == "ARCHIVE"

        aud = act["buildDistributionAudience"] || "(none — archive is not distributed)"
        "archive -> #{aud}"
      end.compact
      line = actions.empty? ? "no archive action" : actions.join("; ")
      puts format("  %-28s enabled=%-6s %s", wa["name"], wa["isEnabled"].to_s, line)
    end
  else
    puts "  no Xcode Cloud product visible to this key"
  end
rescue StandardError => e
  puts "  could not read Xcode Cloud workflows (#{e.class}) — the build rows above still stand"
end

puts
if blocked.empty?
  puts "Every build above is attachable. If the dialog still refuses, the cause is"
  puts "not the build: check the API key's role (a Developer-role key cannot edit a"
  puts "version) or try the dialog in Safari."
else
  puts "#{blocked.length} build(s) cannot be attached, for the reasons above."
  if blocked.any? { |(_, r)| r.any? { |x| x.start_with?("INTERNAL_ONLY") } }
    puts
    puts "INTERNAL_ONLY is not fixable on the build. A build distributed for"
    puts "internal testing only can never be attached to an App Store version —"
    puts "it has to be rebuilt by a workflow set to deploy to TestFlight AND the"
    puts "App Store. In App Store Connect: Xcode Cloud -> the workflow -> Archive"
    puts "action -> Deployment Preparation -> 'TestFlight and App Store'. Then"
    puts "push the release branch again for a fresh build."
  end
  if blocked.any? { |(_, r)| r.include?("missing export compliance") }
    puts
    puts "Missing export compliance is fixable two ways:"
    puts "  - per build, by hand: TestFlight -> the build -> answer the encryption question"
    puts "  - for every future build: ITSAppUsesNonExemptEncryption in the archive's"
    puts "    Info.plist. This project already sets it, so any build uploaded before"
    puts "    that landed has to be answered by hand or replaced."
  end
end
