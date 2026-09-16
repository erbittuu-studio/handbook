#!/usr/bin/env ruby
# frozen_string_literal: true

# Read-only. Answers one question: does App Store Connect currently have a
# version that `deliver` is allowed to write to?
#
#   ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_CONTENT   App Store Connect API key
#   bundle exec ruby scripts/ci/asc_release_state.rb
#
# Once a version is submitted, App Store Connect stops offering an editable
# one, and every metadata/screenshot push dies with a nil error — the app is
# in review, which is normal and shouldn't turn a push red. So the store jobs
# ask first and skip cleanly.
#
# Uses spaceship rather than raw HTTP: `get_edit_app_store_version` filters on
# a specific list of appVersionState values that Apple can add to, and
# re-deriving that list here would be a second source of truth.
#
# EXIT CODES: 0 = question answered (editable or not, both are answers).
# 1 = question could NOT be answered (bad key, app missing, API down) — a
# skip is not a pass, so the store job must still fail on this.

require "base64"
require "json"

begin
  require "spaceship"
rescue LoadError
  warn "spaceship is not available — run this with `bundle exec`"
  exit 1
end

# Turn whatever ASC_KEY_CONTENT actually holds into PEM OpenSSL will read.
# Copied from asc_builds.rb (handles escaped newlines, base64-with-no-markers,
# and unwrapped single-line bodies) rather than shared, so each script in this
# folder stays readable alone.
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

  return key if key.lines.count { |l| !l.strip.empty? } > 2

  body = key.sub(/\A.*?-----BEGIN [A-Z ]*PRIVATE KEY-----/m, "") # gitleaks:allow — marker string
            .sub(/-----END [A-Z ]*PRIVATE KEY-----.*\z/m, "")    # gitleaks:allow — marker string
            .gsub(/\s+/, "")
  return key if body.empty?

  ["-----BEGIN PRIVATE KEY-----",                                # gitleaks:allow — marker string
   body.scan(/.{1,64}/),
   "-----END PRIVATE KEY-----"].flatten.join("\n") + "\n"       # gitleaks:allow — marker string
end

def output(key, value)
  path = ENV["GITHUB_OUTPUT"]
  File.open(path, "a") { |f| f.puts("#{key}=#{value}") } if path && !path.empty?
end

def summary(line)
  path = ENV["GITHUB_STEP_SUMMARY"]
  File.open(path, "a") { |f| f.puts(line) } if path && !path.empty?
end

missing = %w[ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_CONTENT].select { |k| ENV[k].to_s.strip.empty? }
unless missing.empty?
  warn "::error::missing #{missing.join(', ')} — cannot ask App Store Connect anything"
  exit 1
end

bundle_id = JSON.parse(File.read(File.expand_path("../../Project.json", __dir__)))
                .dig("app", "bundleId")

begin
  Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.create(
    key_id: ENV["ASC_KEY_ID"],
    issuer_id: ENV["ASC_ISSUER_ID"],
    key: normalize_pem(ENV["ASC_KEY_CONTENT"])
  )
  app = Spaceship::ConnectAPI::App.find(bundle_id)
  raise "no app with bundle id #{bundle_id}" if app.nil?

  # Exactly what deliver will do, by asking the same method.
  edit = app.get_edit_app_store_version
  # For the message only. An app with no versions at all is a legitimate state
  # (nothing submitted yet), so this must not raise.
  latest = app.get_app_store_versions.first
rescue StandardError => e
  warn "::error::could not read the release state from App Store Connect: #{e.class}: #{e.message}"
  exit 1
end

if edit
  puts "editable: #{edit.version_string} is #{edit.app_version_state}"
  output("editable", "true")
  output("version", edit.version_string)
  output("state", edit.app_version_state)
  exit 0
end

state = latest&.app_version_state || "NO_VERSION"
version = latest&.version_string || "none"

puts "not editable: #{version} is #{state}"
puts "App Store Connect offers no editable version, so there is nothing to push."
output("editable", "false")
output("version", version)
output("state", state)

summary("### Store push skipped")
summary("")
summary("Version **#{version}** is `#{state}`, so App Store Connect has no editable")
summary("version and `deliver` has nothing to write to. This is expected while an")
summary("app is in review — the push will happen on the next run after Apple")
summary("responds, or after you create the next version.")
exit 0
