require 'json'
require 'open3'

def list_stereoisomers(base)
  command = ["python3", File.expand_path("../../scripts/stereoisomers.py", __dir__), base]
  stdout, stderr, status = Open3.capture3(*command)

  if status.success?
    JSON.parse(stdout)
  else
    raise "Python script failed: #{stderr}"
  end
end
