require 'fileutils'
require 'sqlite3'
require 'base64'
require 'open3'
require 'json'

require_relative 'sql'

def optimize_svg(svg_content)
  cmd = ['svgo', '--input', '-', '--output', '-']
  stdout, stderr, status = Open3.capture3(*cmd, stdin_data: svg_content)
  unless status.success?
    raise "SVGO failed: #{stderr}"
  end
  stdout
end

def svg_with_white_background(svg_content)
  doc = Nokogiri::XML(svg_content)
  svg = doc.at('svg') or raise 'No <svg> element found'

  # Ensure viewBox exists and is usable
  view_box = svg['viewBox']
  unless view_box
    w = svg['width'].to_s[/\d+(\.\d+)?/] || '100'
    h = svg['height'].to_s[/\d+(\.\d+)?/] || '100'
    svg['viewBox'] = "0 0 #{w} #{h}"
  end

  # Set full size behavior
  svg['width']  = '100%'
  svg['height'] = '100%'
  svg['style']  = 'display: block;' # prevents gaps inside <td>
  svg['preserveAspectRatio'] = 'none'

  # Add white background rectangle
  bg = Nokogiri::XML::Node.new('rect', doc)
  bg['x'], bg['y'], bg['width'], bg['height'], bg['fill'] = '0', '0', '100%', '100%', 'white'
  svg.children.first.add_previous_sibling(bg)

  doc.to_xml
end

# Where each kind of class index lives and which record key lists its members.
VCLASSES = [
  { "Path" => "class", "JName" => "Classes" },
  { "Path" => "substituted", "JName" => "ChemicalClasses" },
]

def load_db_substances
  db = SQLite3::Database.new $options[:d]
  db.execute <<-SQL
    CREATE TABLE IF NOT EXISTS substances (
      id INTEGER PRIMARY KEY,
      title TEXT UNIQUE,
      aliases TEXT,
      data_json TEXT
    );
  SQL
  db.execute("SELECT data_json FROM substances").map { |row| JSON.parse(row[0]) }
end

# Pharmacological classes are maintained by hand in index/substance.json and
# only reach the db when a substance is searched again, so the list there wins
# and substances that were never searched are still indexed.
def load_index_substances
  records = load_db_substances
  return records unless File.exist?('index/substance.json')
  by_title = records.to_h { |record| [record["Title"].to_s.downcase, record] }
  for ssub in JSON.parse(File.read('index/substance.json'))["Entries"]
    next if ssub["Title"] == nil || !ssub["Classes"].is_a?(Array)
    record = by_title[ssub["Title"].downcase]
    if record == nil
      record = { "Title" => ssub["Title"], "Abbreviation" => ssub["Abr"] }
      records << record
    end
    record["Classes"] = ssub["Classes"]
  end
  records
end

def class_names(record, vclass)
  record[vclass].is_a?(Array) ? record[vclass].map { |c| c.to_s.downcase } : []
end

def class_index_file(pclass, iclass)
  name = iclass.downcase
  spaced = "#{pclass}/#{name}.json"
  File.exist?(spaced) ? spaced : "#{pclass}/#{name.gsub(/\s+/, '_')}.json"
end

# Merges the substances that list iclass under vclass into
# #{pclass}/#{iclass}.json. Existing entries are kept, so a partial db never
# empties an index.
def index_class(pclass, vclass, iclass, records = load_index_substances)
  iclass = iclass.downcase
  members = records.select { |record| class_names(record, vclass).include?(iclass) }
  file = class_index_file(pclass, iclass)
  if members.empty?
    puts "No substances found for #{file}, left as is"
    return false
  end

  index = File.exist?(file) ? JSON.parse(File.read(file)) : {}
  index['Name'] ||= iclass
  index['Entries'] ||= []
  for record in members
    member = { "Title" => record["Title"], "Abr" => record["Abbreviation"], "MW" => record["MolecularWeight"] }.compact
    first = index['First']
    if first.is_a?(Hash) && first['Title'].to_s.downcase == member["Title"].downcase
      first.merge!(member)
      next
    end
    entry = index['Entries'].find { |e| e['Title'].to_s.downcase == member["Title"].downcase }
    entry ? entry.merge!(member) : index['Entries'] << member
  end
  File.write(file, JSON.pretty_generate(index))
  puts "Indexed #{file}: #{members.length} matched, #{index['Entries'].length} entries"
  true
end

# name may be a class, or a substance whose classes should be indexed.
# Without a name every class that a substance belongs to is indexed.
def index_classes(name = nil)
  records = load_index_substances
  targets = []
  for vclass in VCLASSES
    known = records.flat_map { |record| class_names(record, vclass["JName"]) }.uniq
    if name == nil
      targets += known.map { |iclass| [vclass, iclass] }
    elsif known.include?(name.downcase) || File.exist?(class_index_file(vclass["Path"], name))
      targets << [vclass, name]
    end
  end
  if targets.empty? && name != nil
    substance = records.find { |record| record["Title"].to_s.downcase == name.downcase }
    for vclass in VCLASSES
      targets += class_names(substance, vclass["JName"]).map { |iclass| [vclass, iclass] } if substance
    end
  end
  puts "Nothing to index for #{name}: not a class, and not a substance with classes" if targets.empty? && name != nil
  for vclass, iclass in targets
    index_class(vclass["Path"], vclass["JName"], iclass, records)
  end
end
