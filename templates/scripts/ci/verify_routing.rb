#!/usr/bin/env ruby
# frozen_string_literal: true

# Checks that a push of each kind starts exactly the pipelines it should.
#
# Everything a push can start is decided in one place — the paths filter in
# main.yml — including the TestFlight build, because Xcode Cloud is manual-only
# and GitHub starts it. That is the point of this check: one source of truth,
# and proof it says what we think it says.
#
# It reads the real config rather than restating it, so it cannot drift from
# what actually runs. Expectations live below; a mismatch fails.
#
#   ruby scripts/ci/verify_routing.rb

require "yaml"

ROOT = File.expand_path("../..", __dir__)
MAIN = YAML.load_file(File.join(ROOT, ".github/workflows/main.yml"))

TRIGGER_PATHS = MAIN[true]["push"]["paths"]
FILTERS = YAML.safe_load(
  MAIN["jobs"]["changes"]["steps"].find { |s| s["uses"].to_s.include?("paths-filter") }["with"]["filters"]
)

def glob_match?(path, pattern)
  File.fnmatch?(pattern, path, File::FNM_PATHNAME | File::FNM_EXTGLOB) ||
    (pattern.end_with?("/**") && path.start_with?(pattern.delete_suffix("**"))) ||
    File.fnmatch?(pattern, path, File::FNM_EXTGLOB)
end

def triggers_workflow?(files)
  files.any? { |f| TRIGGER_PATHS.any? { |p| glob_match?(f, p) } }
end

def filter_hit?(files, name)
  patterns = Array(FILTERS[name])
  files.any? { |f| patterns.any? { |p| glob_match?(f, p) } }
end

def route(files)
  return { workflow: false } unless triggers_workflow?(files)

  # What changed decides what runs — the same on every branch. There is one
  # hosting address, so there is nothing branch-specific left to decide.
  { workflow: true,
    metadata: filter_hit?(files, "metadata"),
    screenshots: filter_hit?(files, "screenshots"),
    code: filter_hit?(files, "code"),
    hosting: filter_hit?(files, "data") || filter_hit?(files, "config") }
end

SCENARIOS = [
  { name: "data only",            files: ["Data/source/bugs/bugs_0.svg"],
    build: false, hosting: true,  metadata: false },
  { name: "metadata only",        files: ["fastlane/metadata/en-US/description.txt"],
    build: false, hosting: false, metadata: true },
  { name: "screenshots only",     files: ["fastlane/screenshots/en-US/01.png"],
    build: false, hosting: false, metadata: false },
  { name: "config only",          files: ["App/Resources/config.json"],
    build: false, hosting: true,  metadata: false },
  { name: "code only",            files: ["App/Source/Features/Canvas/CanvasView.swift"],
    build: true,  hosting: false, metadata: false },
  { name: "docs only",            files: ["README.md"],
    build: false, hosting: false, metadata: false },
  { name: "data + metadata",      files: ["Data/source/bugs/bugs_0.svg",
                                          "fastlane/metadata/en-US/description.txt"],
    build: false, hosting: true,  metadata: true },
  { name: "data + code",          files: ["Data/source/bugs/bugs_0.svg",
                                          "App/Source/App/{{PROJECT_NAME}}App.swift"],
    build: true,  hosting: true,  metadata: false },
  { name: "metadata + code",      files: ["fastlane/metadata/en-US/description.txt",
                                          "App/Source/App/{{PROJECT_NAME}}App.swift"],
    build: true,  hosting: false, metadata: true },
  { name: "everything",           files: ["Data/source/bugs/bugs_0.svg",
                                          "fastlane/metadata/en-US/description.txt",
                                          "fastlane/screenshots/en-US/01.png",
                                          "App/Resources/config.json",
                                          "App/Source/App/{{PROJECT_NAME}}App.swift"],
    build: true,  hosting: true,  metadata: true }
].freeze

failures = []
puts format("  %-18s %-7s %-9s %-9s %-11s %s",
            "push contains", "build", "hosting", "metadata", "screenshots", "")
puts "  #{'-' * 72}"

SCENARIOS.each do |scenario|
  files = scenario[:files]
  release = route(files)
  # A build is started by main.yml when app code changed — nothing else.
  build = release[:workflow] ? release[:code] : false

  hosting = release[:workflow] ? release[:hosting] : false
  metadata = release[:workflow] ? release[:metadata] : false

  ok = build == scenario[:build] &&
       hosting == scenario[:hosting] &&
       metadata == scenario[:metadata]
  failures << scenario[:name] unless ok

  puts format("  %-18s %-7s %-9s %-9s %-11s %s",
              scenario[:name], build, hosting, metadata,
              release[:workflow] ? release[:screenshots] : false,
              ok ? "ok" : "MISMATCH")
  next if ok

  puts format("      expected build=%s hosting=%s metadata=%s",
              scenario[:build], scenario[:hosting], scenario[:metadata])
end

puts
if failures.empty?
  puts "  All #{SCENARIOS.size} push shapes route correctly."
  exit 0
end
puts "  #{failures.size} mismatch(es): #{failures.join(', ')}"
exit 1
