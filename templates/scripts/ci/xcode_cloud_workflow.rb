#!/usr/bin/env ruby
# frozen_string_literal: true

# Reads and edits Xcode Cloud's start conditions through the App Store Connect
# API, so the setting lives in git rather than in somebody's memory of which
# checkbox they ticked.
#
# What it's for: narrowing a workflow so it only builds when the app itself
# changed — the original Release workflow had no file rule, so every push to a
# release branch cost a full archive and a build number. Making it
# manual-only doesn't work (the API accepts a null start condition, reports
# success, and leaves it untouched); narrowing the existing condition does.
#
#   ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_CONTENT   App Store Connect API key
#
#   ruby xcode_cloud_workflow.rb --show                 print current settings
#
# Defaults to this app's product; --product <name> picks another.
#   ruby xcode_cloud_workflow.rb --code-only <name>     build only on App/ changes
#   ruby xcode_cloud_workflow.rb --app-store <name>     archive for the App Store
#   ruby xcode_cloud_workflow.rb --restore <file>       put a backup back
#   ruby xcode_cloud_workflow.rb --check <name>         exit 1 unless <name> exists
#                                                        and archives APP_STORE_ELIGIBLE
#
# WHY --check EXISTS: --app-store fixes the audience once run, but the thing
# it fixes has no other symptom until a build sits greyed out in Add Build
# months later. --check is the automatic, read-only half (main.yml's
# xcode-cloud-check job) — fails loud in the regular log, not only
# $GITHUB_STEP_SUMMARY, which has no REST API.
#
# WHY --app-store EXISTS: an archive action's Distribution Preparation has
# three settings, and the middle one is a trap:
#
#   None                              nothing is uploaded
#   TestFlight (Internal Testing Only) uploaded, installable, and stamped
#                                     buildAudienceType=INTERNAL_ONLY — which
#                                     App Store Connect will NEVER let you
#                                     attach to an App Store version
#   App Store Connect                 APP_STORE_ELIGIBLE — and still available
#                                     in TestFlight, to internal and external
#                                     testers both
#
# The middle one is a strictly smaller subset of the last, with nothing
# saying so at the point of choosing — an app on it sends every build to
# TestFlight, then sits greyed out in Add Build. The stamp is applied at
# export, so no existing build can be repaired; a new one has to be made.
#
# BUILT NOT TO BREAK ANYTHING — Apple doesn't document whether a start
# condition can be cleared by sending null, so this doesn't assume it worked:
#
#   1. --show is the default. Nothing is written unless you ask.
#   2. Before any write, the whole workflow is saved to a timestamped JSON
#      file. --restore replays it.
#   3. After the write, the workflow is read back and checked — a success
#      that didn't happen exits non-zero rather than being reported.
#   4. Any API error is printed verbatim, body included.
#
# JWT/HTTP helpers are duplicated from App/ci_scripts/lib/asc_build_number.rb
# deliberately — that script runs inside every archive and decides the build
# number, and breaking it to save lines here would be a poor trade.

require "base64"
require "json"
require "net/http"
require "openssl"
require "time"
require "uri"

CONDITIONS = %w[branchStartCondition tagStartCondition
                pullRequestStartCondition scheduledStartCondition].freeze

def b64url(data)
  Base64.urlsafe_encode64(data).delete("=")
end

def int_to_bytes(value, length)
  [value.to_s(16).rjust(length * 2, "0")].pack("H*")
end

# Turn whatever ASC_KEY_CONTENT actually holds into PEM OpenSSL will read.
# Handles three real shapes: newlines escaped as literal backslash-n, the
# whole .p8 stored base64-encoded with no markers, and a single-line body
# needing 64-character wrapping.
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

def asc(method, path, token, body = nil)
  uri = URI("https://api.appstoreconnect.apple.com#{path}")
  request = case method
            when :get   then Net::HTTP::Get.new(uri)
            when :patch then Net::HTTP::Patch.new(uri)
            else abort "unsupported method #{method}"
            end
  request["Authorization"] = "Bearer #{token}"
  if body
    request["Content-Type"] = "application/json"
    request.body = body.to_json
  end

  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                             open_timeout: 20, read_timeout: 30) { |http| http.request(request) }
  unless response.is_a?(Net::HTTPSuccess)
    abort "App Store Connect API #{response.code} for #{method.upcase} #{path}\n#{response.body}"
  end

  response.body.to_s.empty? ? {} : JSON.parse(response.body)
end

# Like `asc`, but hands back the failure instead of aborting on it. Only
# --app-store needs this: its one likely failure has a specific, actionable
# cause and a raw 409 dump buries it.
def asc_try(method, path, token, body = nil)
  uri = URI("https://api.appstoreconnect.apple.com#{path}")
  request = method == :patch ? Net::HTTP::Patch.new(uri) : Net::HTTP::Get.new(uri)
  request["Authorization"] = "Bearer #{token}"
  if body
    request["Content-Type"] = "application/json"
    request.body = body.to_json
  end
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                             open_timeout: 20, read_timeout: 30) { |http| http.request(request) }
  [response.is_a?(Net::HTTPSuccess), response.code, response.body.to_s]
end

def env_or_abort(name)
  ENV.fetch(name) { abort "#{name} not set" }
end

def describe(attributes)
  active = CONDITIONS.select { |name| attributes[name] }
  return "manual only — Xcode Cloud starts nothing by itself" if active.empty?

  active.map { |name| "#{name}=#{JSON.generate(attributes[name])}" }.join("\n      ")
end

# What each archive action will do with what it builds. Printed on every run,
# because a workflow that uploads to the wrong audience looks completely healthy
# from everywhere else.
def describe_archives(attributes)
  archives = (attributes["actions"] || []).select { |a| a["actionType"] == "ARCHIVE" }
  return "no archive action" if archives.empty?

  archives.map do |action|
    case action["buildDistributionAudience"]
    when "APP_STORE_ELIGIBLE" then "archive -> App Store Connect (also in TestFlight)"
    when "INTERNAL_ONLY"      then "archive -> TestFlight INTERNAL ONLY — cannot be submitted"
    when nil                  then "archive -> None (nothing is uploaded)"
    else "archive -> #{action['buildDistributionAudience']}"
    end
  end.join("\n      ")
end

token = mint_jwt(env_or_abort("ASC_KEY_ID"),
                 env_or_abort("ASC_ISSUER_ID"),
                 env_or_abort("ASC_KEY_CONTENT"))

# --- restore -----------------------------------------------------------------

if (index = ARGV.index("--restore"))
  path = ARGV[index + 1] or abort "usage: --restore <backup.json>"
  saved = JSON.parse(File.read(path))
  id = saved.fetch("id")
  attributes = saved.fetch("attributes").slice(*CONDITIONS)

  asc(:patch, "/v1/ciWorkflows/#{id}", token,
      { "data" => { "type" => "ciWorkflows", "id" => id, "attributes" => attributes } })
  puts "Restored #{saved.dig('attributes', 'name')} from #{path}"
  exit 0
end

# --- discover ----------------------------------------------------------------

# One API key sees every app in the account — seven of them here — so the
# product has to be named. Taking the first one silently pointed this at a
# different app entirely.
PRODUCT = ARGV.index("--product")&.then { |i| ARGV[i + 1] } || "{{PROJECT_NAME}}"
# The folder everything compiled lives in. Anything outside it is content or CI.
BUILD_DIRECTORY = ARGV.index("--dir")&.then { |i| ARGV[i + 1] } || "App"

products = asc(:get, "/v1/ciProducts?limit=200", token)["data"] || []
abort "no Xcode Cloud products visible to this API key" if products.empty?

product = products.find { |candidate| candidate.dig("attributes", "name") == PRODUCT }
unless product
  available = products.map { |candidate| candidate.dig("attributes", "name") }.sort.join(", ")
  abort "no Xcode Cloud product named '#{PRODUCT}'. Available: #{available}"
end

workflows = asc(:get, "/v1/ciProducts/#{product['id']}/workflows?limit=200", token)["data"] || []
abort "no workflows on #{product.dig('attributes', 'name')}" if workflows.empty?

puts "product: #{product.dig('attributes', 'name')} (#{product['id']})"

target       = ARGV.index("--code-only")&.then { |i| ARGV[i + 1] }
store_target = ARGV.index("--app-store")&.then { |i| ARGV[i + 1] }
raw_target   = ARGV.index("--raw")&.then { |i| ARGV[i + 1] }
check_target = ARGV.index("--check")&.then { |i| ARGV[i + 1] }

workflows.each do |workflow|
  attributes = workflow["attributes"] || {}
  puts "  workflow: #{attributes['name']} (#{workflow['id']})  enabled=#{attributes['isEnabled']}"
  puts "      #{describe(attributes)}"
  puts "      #{describe_archives(attributes)}"
end

# --check: everything printed above already, so a failure here is never a
# mystery — the full report is right there in the same log, not hidden in
# $GITHUB_STEP_SUMMARY the way the once-hand-parsed version of this check was.
if check_target
  workflow = workflows.find { |w| w.dig("attributes", "name") == check_target }
  unless workflow
    available = workflows.map { |w| w.dig("attributes", "name") }.join(", ")
    abort "\nno workflow named '#{check_target}'. Available: #{available}\n" \
          "Create it in Xcode Cloud (PLAYBOOK §12), or run --app-store on the " \
          "one that should be renamed."
  end

  archive = (workflow.dig("attributes", "actions") || []).find { |a| a["actionType"] == "ARCHIVE" }
  unless archive
    abort "\n'#{check_target}' exists but has no archive action — nothing it builds can ever reach TestFlight."
  end
  unless archive["buildDistributionAudience"] == "APP_STORE_ELIGIBLE"
    abort "\n'#{check_target}' archives #{archive['buildDistributionAudience'].inspect}, not APP_STORE_ELIGIBLE — " \
          "every build it makes will sit unattachable in Add Build. " \
          "Fix: ruby #{$PROGRAM_NAME} --app-store #{check_target}"
  end
  unless workflow.dig("attributes", "isEnabled")
    abort "\n'#{check_target}' exists and archives correctly but is disabled — nothing will build from it."
  end

  puts "\n'#{check_target}' exists, is enabled, and archives APP_STORE_ELIGIBLE."
  exit 0 unless target || store_target
end

# --raw: print the workflow exactly as the API returns it. Apple documents the
# CiWorkflow attributes only partially, and the archive audience is not where
# the obvious reading of the schema puts it — a PATCH built on a guess comes
# back "Deployment configured for unknown action" with no hint as to the right
# shape. Read it, then write it.
if raw_target
  workflow = workflows.find { |w| w.dig("attributes", "name") == raw_target }
  abort "no workflow named '#{raw_target}'" unless workflow
  puts "\n--- #{raw_target} as the API returns it ---"
  puts JSON.pretty_generate(workflow)
  exit 0 unless target || store_target
end

unless target || store_target
  puts
  puts "Nothing was changed."
  puts "  --code-only <workflow name>   build only on App/ changes"
  puts "  --app-store <workflow name>   archive to App Store Connect, not internal-only"
  exit 0
end

def find_workflow!(workflows, name)
  found = workflows.find { |w| w.dig("attributes", "name") == name }
  return found if found

  available = workflows.map { |w| w.dig("attributes", "name") }.join(", ")
  abort "no workflow named '#{name}'. Available: #{available}"
end

def back_up!(workflow, name)
  stamp = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
  path  = "xcode-cloud-#{name.gsub(/\W+/, '-')}-#{stamp}.json"
  File.write(path, JSON.pretty_generate(workflow))
  puts "\nBacked up to #{path} — `--restore #{path}` puts it back."
  path
end

# --- --app-store -------------------------------------------------------------
#
# Same discipline as the start-condition edit below: back up, write, then read
# back and check, because a PATCH that reports success is not evidence.
if store_target
  workflow = find_workflow!(workflows, store_target)
  back_up!(workflow, store_target)

  actions = (workflow.dig("attributes", "actions") || []).map do |action|
    next action unless action["actionType"] == "ARCHIVE"

    action.merge("buildDistributionAudience" => "APP_STORE_ELIGIBLE")
  end
  abort "'#{store_target}' has no archive action to change" if actions.none? { |a| a["actionType"] == "ARCHIVE" }

  ok, code, body = asc_try(:patch, "/v1/ciWorkflows/#{workflow['id']}", token,
                           { "data" => { "type" => "ciWorkflows", "id" => workflow["id"],
                                         "attributes" => { "actions" => actions } } })

  unless ok
    # Apple validates an attribute it won't show you — `deploymentConfig`
    # never appears in the GET response, so every payload here is a guess.
    if body.include?("deploymentConfig") || body.include?("unknown action")
      warn <<~MESSAGE

        App Store Connect refused the change (HTTP #{code}).

            "Deployment configured for unknown action" — /data/attributes/deploymentConfig

        This is Apple's end, not the payload, and it is not worth another
        attempt. The API contradicts itself — both halves verified against the
        live endpoint on 31 Aug 2026:

            PATCH actions             -> 409 "Deployment configured for unknown
                                         action", pointing at deploymentConfig
            PATCH deploymentConfig    -> 409 "'deploymentConfig' is not an
                                         attribute on the resource 'ciWorkflows'"

        It demands an attribute it refuses to accept, and never returns that
        attribute on a GET, so there is nothing to round-trip either. Sending
        actions with deploymentConfig null, with it named, and alone were all
        tried; all three were refused and none altered anything.

        The archive audience cannot be set through the API.

        Set it by hand, once — it is a radio button and it stays set:

            App Store Connect -> Xcode Cloud -> Manage Workflows -> #{store_target}
              -> Archive - iOS -> Distribution Preparation -> App Store Connect

        Then run this script with no flags to confirm it reads back as
        "archive -> App Store Connect", and make a new build: the audience is
        stamped at export, so no existing build is changed by fixing this.
      MESSAGE
      exit 2
    end
    abort "App Store Connect API #{code} for PATCH /v1/ciWorkflows/#{workflow['id']}\n#{body}"
  end

  after = asc(:get, "/v1/ciWorkflows/#{workflow['id']}", token).dig("data", "attributes") || {}
  still_internal = (after["actions"] || [])
                   .select { |a| a["actionType"] == "ARCHIVE" }
                   .reject { |a| a["buildDistributionAudience"] == "APP_STORE_ELIGIBLE" }

  puts "      #{describe_archives(after)}"
  unless still_internal.empty?
    abort "the archive action is still not App Store eligible — the PATCH reported success and changed nothing"
  end
  puts "\n'#{store_target}' now archives to App Store Connect."
  puts "Builds already uploaded keep the audience they were exported with; make a new one."
  exit 0 unless target
end

workflow = find_workflow!(workflows, target)

# --- back up, then write -----------------------------------------------------

back_up!(workflow, target)

condition = workflow.dig("attributes", "branchStartCondition")
abort "'#{target}' has no branch start condition to narrow" unless condition

# Everything the app is built from lives under App/ — a push touching only
# Data/, fastlane/ or .github/ shouldn't cost an archive and a build number.
# Clearing the condition entirely doesn't work (the API accepts a null and
# leaves it unchanged); narrowing it does.
updated = condition.merge(
  "filesAndFoldersRule" => {
    "mode" => "START_IF_ANY_FILE_MATCHES",
    "matchers" => [{ "directory" => BUILD_DIRECTORY, "fileExtension" => nil, "fileName" => nil }]
  }
)

asc(:patch, "/v1/ciWorkflows/#{workflow['id']}", token,
    { "data" => { "type" => "ciWorkflows", "id" => workflow["id"],
                  "attributes" => { "branchStartCondition" => updated } } })

# --- verify, do not assume ---------------------------------------------------

after = asc(:get, "/v1/ciWorkflows/#{workflow['id']}", token).dig("data", "attributes") || {}
rule = after.dig("branchStartCondition", "filesAndFoldersRule")

if rule && rule["mode"] == "START_IF_ANY_FILE_MATCHES" &&
   rule["matchers"].to_a.any? { |m| m["directory"] == BUILD_DIRECTORY }
  puts "'#{target}' now builds only when #{BUILD_DIRECTORY}/ changes."
  puts "Pages, store text and CI no longer start a build."
  exit 0
end

warn "\nThe API accepted the change but the rule did not take:"
warn "  #{JSON.generate(rule)}"
warn "Set it in App Store Connect instead: Xcode Cloud > #{target} > Edit >"
warn "Start Conditions > Files and Folders. The backup above is unchanged."
exit 1
