#!/usr/bin/env ruby
# frozen_string_literal: true

# Checks that a push of each kind starts exactly the jobs it should.
#
# What a push starts is decided in one place — the paths filter in main.yml —
# including the TestFlight build, because Xcode Cloud is manual-only and GitHub
# starts it. That is the point of this check: one source of truth, and proof it
# says what we think it says.
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

# What changed decides what runs — the same on every branch.
def route(files)
  return { workflow: false, code: false, ci: false } unless triggers_workflow?(files)

  { workflow: true, code: filter_hit?(files, "code"), ci: filter_hit?(files, "ci") }
end

# Store listing text and screenshots are not part of this repo any more (they
# live in Firebase), so a push never starts anything for them.
SCENARIOS = [
  { name: "code only",        files: ["App/Source/App/{{APP_NAME}}App.swift"],
    build: true,  ci: false },
  { name: "docs only",        files: ["README.md"],
    build: false, ci: false },
  { name: "CI script only",   files: ["scripts/ci/asc_builds.rb"],
    build: false, ci: true },
  { name: "workflow only",    files: [".github/workflows/main.yml"],
    build: false, ci: true },
  { name: "project.yml",      files: ["project.yml"],
    build: false, ci: true },
  { name: "code + CI script", files: ["App/Source/App/{{APP_NAME}}App.swift", "scripts/ci/asc_builds.rb"],
    build: true,  ci: true }
].freeze

failures = []
puts format("  %-18s %-7s %-7s %s", "push contains", "build", "ci", "")
puts "  #{'-' * 44}"

SCENARIOS.each do |scenario|
  release = route(scenario[:files])
  # A build is started by main.yml when app code changed — nothing else.
  ok = release[:code] == scenario[:build] && release[:ci] == scenario[:ci]
  failures << scenario[:name] unless ok

  puts format("  %-18s %-7s %-7s %s", scenario[:name], release[:code], release[:ci], ok ? "ok" : "MISMATCH")
  puts format("      expected build=%s ci=%s", scenario[:build], scenario[:ci]) unless ok
end

puts
if failures.empty?
  puts "  All #{SCENARIOS.size} push shapes route correctly."
  exit 0
end
puts "  #{failures.size} mismatch(es): #{failures.join(', ')}"
exit 1
