require 'optparse'
require 'fileutils'

require_relative 'config'

def handle_args()
  OptionParser.new do |opts|
    opts.banner = "Usage: chrp.[OPTIONS] [ARGUMENTS]"
    opts.on("-h", "--help",       "Displays help message") do
      puts opts
      exit
    end
    opts.on("-v", "--verbose",    "Enable verbose logging") do
      $options[:v] = true
    end
    # --cache and --database are expanded here, before the chdir into the frontend,
    # so relative paths refer to where chrp was invoked
    opts.on("-c", "--cache PATH", "Set cache path") do |c|
      $options[:c] = File.expand_path(c)
    end
    opts.on("-f", "--frontend PATH", "Set frontend path (default: current directory)") do |f|
      $options[:f] = f
    end
    opts.on("-d", "--database PATH", "Set database path (default: db.sqlite in the frontend)") do |d|
      $options[:d] = File.expand_path(d)
    end
    opts.on("-mMODE", "--mode=MODE",       "Set mode of operation") do |m|
      $options[:m] = m
    end
    opts.on("-s", "--skip SOURCES", Array, "Skip sources, comma separated (dbi-igs, protestkit)") do |s|
      $options[:s] = s.map(&:downcase)
    end
    opts.on("--molpic COMMAND", "Set molpic command (default: java -jar molpic.jar)") do |c|
      $options[:molpic] = c
    end
  end.parse!

  if $options[:f]
    abort "chrp: frontend path is not a directory: #{$options[:f]}" unless Dir.exist?($options[:f])
    Dir.chdir($options[:f])
  end

  if ["search", "research", "uncache"].include?($options[:m]) && !File.exist?("index/substance.json")
    abort "chrp: no index/substance.json in #{Dir.pwd}, run from the frontend directory or pass --frontend PATH"
  end

  if $options[:m] == "index"
    if ARGV.empty?
    #  puts "Missing indexclass argument"
    #  exit
    else
      $to_index = [ ARGV.join(" ") ]
    end
  end

  if $options[:m] == "search"
    if ARGV.empty?
      #puts "Missing searchterm argument"
      #exit
    else
      $compounds = [ ARGV[0] ]
    end
  end

  if $options[:c]
    if $options[:v]
      puts "Cache: " + $options[:c]
    end
    FileUtils.mkdir_p($options[:c])
  end
end
