require 'open3'
require 'tmpdir'
require 'fileutils'
require 'rbconfig'

# Runs chrp against a throwaway frontend. The index is empty, so nothing is fetched.
ROOT = File.expand_path('..', __dir__)

def chrp(*args, chdir:)
  Open3.capture2e(RbConfig.ruby, File.join(ROOT, 'exe/chrp'), *args, chdir: chdir)
end

def database_path(*args, chdir:)
  script = 'handle_args; puts File.expand_path($options[:d])'
  out, _ = Open3.capture2e(RbConfig.ruby, '-r', File.join(ROOT, 'lib/chrp/args'), '-e', script, '--', *args, chdir: chdir)
  out.strip
end

def molpic_option(*args, chdir:)
  script = 'handle_args; puts $options[:molpic].inspect'
  out, _ = Open3.capture2e(RbConfig.ruby, '-r', File.join(ROOT, 'lib/chrp/args'), '-e', script, '--', *args, chdir: chdir)
  out.strip
end

def check(desc, ok, out = "")
  puts "#{ok ? 'ok' : 'FAILED'}: #{desc}"
  return if ok
  puts out
  exit 1
end

Dir.mktmpdir do |tmp|
  tmp = File.realpath(tmp)
  frontend = File.join(tmp, 'frontend')
  elsewhere = File.join(tmp, 'elsewhere')
  FileUtils.mkdir_p([File.join(frontend, 'index'), elsewhere])
  %w[substance composite].each { |n| File.write(File.join(frontend, "index/#{n}.json"), '{"Entries": []}') }

  out, status = chrp('-v', '--frontend', frontend, chdir: elsewhere)
  check("--frontend finds index/substance.json from another directory", status.success? && out.include?("list: 0"), out)

  out, status = chrp('-v', chdir: frontend)
  check("works from inside the frontend without --frontend", status.success? && out.include?("list: 0"), out)

  out, status = chrp(chdir: elsewhere)
  check("missing index names --frontend instead of a stack trace", !status.success? && out.include?("--frontend") && !out.include?("ENOENT"), out)

  out, status = chrp('--frontend', File.join(tmp, 'nope'), chdir: elsewhere)
  check("nonexistent --frontend is reported without a stack trace", !status.success? && !out.include?("ENOENT"), out)

  File.write(File.join(frontend, 'index/substance.json'), '{"Entries": [{"Title": "Testine", "Classes": ["Stimulant"]}]}')
  FileUtils.mkdir_p(File.join(frontend, 'class'))
  db = File.join(elsewhere, 'idx.sqlite')
  out, status = chrp('--frontend', frontend, '--database', db, '--mode=index', 'Stimulant', chdir: elsewhere)
  index = File.join(frontend, 'class/stimulant.json')
  check("index writes the class index into the frontend", status.success? && File.exist?(index) && File.read(index).include?("Testine"), out)
  check("index uses the --database path", File.exist?(db) && !File.exist?(File.join(frontend, 'db.sqlite')), out)

  out = database_path('--frontend', frontend, chdir: elsewhere)
  check("database defaults to db.sqlite in the frontend", out == File.join(frontend, 'db.sqlite'), out)

  out = database_path('--frontend', frontend, '--database', 'my.sqlite', chdir: elsewhere)
  check("relative --database resolves against the invocation directory", out == File.join(elsewhere, 'my.sqlite'), out)

  out = database_path('--frontend', frontend, '--cache', 'cache', chdir: elsewhere)
  check("relative --cache resolves against the invocation directory", Dir.exist?(File.join(elsewhere, 'cache')) && !Dir.exist?(File.join(frontend, 'cache')), out)

  out = molpic_option('--frontend', frontend, '--molpic', 'molpic --fast', chdir: elsewhere)
  check("--molpic sets the molpic command", out == '"molpic --fast"', out)

  out = molpic_option('--frontend', frontend, chdir: elsewhere)
  check("molpic command is unset by default", out == 'nil', out)
end
