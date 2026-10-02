#!/usr/bin/env ruby
# frozen_string_literal: true

# Checks the contract between the thin workflow callers an app gets (templates/workflows) and the reusable
# workflows they call (.github/workflows/app-*.yml). A mismatch only shows on GitHub otherwise, so it is checked here:
#
#   - every caller job calls the reusable of the same name at this handbook's pinned version, with secrets inherited
#   - the reusable exists, is callable, and every input the caller passes is declared; every required one is passed
#   - the caller grants the permissions the reusable asks for, since a called workflow can only narrow them
#
#   ruby scripts/check-workflows.rb

require "yaml"

ROOT = File.expand_path("..", __dir__)
problems = []

Dir[File.join(ROOT, "templates/workflows/*.yml")].sort.each do |path|
  name = File.basename(path, ".yml")
  caller_file = YAML.load_file(path)
  label = "templates/workflows/#{name}.yml"
  expected = "erbittuu-studio/handbook/.github/workflows/app-#{name}.yml@v{{PES_VERSION}}"
  reusable_path = File.join(ROOT, ".github/workflows/app-#{name}.yml")

  unless File.exist?(reusable_path)
    problems << "#{label}: no .github/workflows/app-#{name}.yml to call"
    next
  end
  reusable = YAML.load_file(reusable_path)
  trigger = reusable[true] || reusable["on"]
  callable = trigger.is_a?(Hash) && trigger.key?("workflow_call")
  declared = callable ? ((trigger["workflow_call"] || {})["inputs"] || {}) : nil
  problems << "app-#{name}.yml is not a workflow_call workflow" unless callable

  caller_file["jobs"].each do |job_id, job|
    problems << "#{label}: job #{job_id} calls #{job['uses']}, expected #{expected}" unless job["uses"] == expected
    problems << "#{label}: job #{job_id} must pass `secrets: inherit`" unless job["secrets"] == "inherit"
    passed = (job["with"] || {}).keys
    (declared || {}).each do |input, spec|
      problems << "#{label}: required input #{input} is not passed" if spec["required"] && !passed.include?(input)
    end
    (passed - (declared || {}).keys).each { |input| problems << "#{label}: passes #{input}, which app-#{name}.yml does not declare" }
  end

  granted = caller_file["permissions"] || {}
  (reusable["permissions"] || {}).each do |scope, level|
    have = granted[scope]
    ok = have == level || (have == "write" && level == "read")
    problems << "#{label}: grants #{scope}=#{have.inspect} but app-#{name}.yml needs #{level}" unless ok
  end
  reusable["jobs"].each_value do |job|
    (job["permissions"] || {}).each do |scope, level|
      have = granted[scope]
      ok = have == level || (have == "write" && level == "read")
      problems << "#{label}: grants #{scope}=#{have.inspect} but a job in app-#{name}.yml needs #{level}" unless ok
    end
  end
end

puts problems.map { |p| "  #{p}" }
exit(problems.empty? ? 0 : 1)
