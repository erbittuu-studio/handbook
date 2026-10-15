require "yaml"

def pes_app_name
  dir = File.expand_path(__dir__)
  dir = File.dirname(dir) until File.exist?(File.join(dir, "project.yml")) || dir == "/"
  path = File.join(dir, "project.yml")
  name = YAML.safe_load(File.read(path), aliases: true).dig("app", "name") if File.exist?(path)
  name || abort("no app.name in project.yml; pass --product <name>")
end
