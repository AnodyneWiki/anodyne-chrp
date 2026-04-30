require 'fileutils'
require 'sqlite3'
require 'base64'
require 'open3'

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

def index_class(pclass, vclass, iclass)
  index_substances = []
  index = {} 
  db = SQLite3::Database.new 'db.sqlite'
  db.execute <<-SQL
    CREATE TABLE IF NOT EXISTS substances (
      id INTEGER PRIMARY KEY,
      title TEXT UNIQUE,
      aliases TEXT,
      data_json TEXT
    );
  SQL
  iclass = iclass.downcase
  mods_data = {}
  vars_data = {}
  if File.exist?("#{pclass}/#{iclass.downcase}.json")
    index_file_content = File.read("#{pclass}/#{iclass.downcase}.json")
    index = JSON.parse(index_file_content)
  end
  index['Name'] = iclass.downcase

  Dir.glob('structure/*.svg').each do |svg_path|
    begin
      wildtitle = Pathname(svg_path).basename.to_s.gsub("_", " ").delete_suffix(".svg")
      next if wildtitle.start_with?("(-)-")
      next if wildtitle.start_with?("(+)-")
      full_data = {}
      svg_content = File.read(svg_path)
      optimized = optimize_svg(formated)
      puts wildtitle
      query_struct = <<-SQL
        SELECT title, aliases, data_json
        FROM substances
        WHERE title = '#{wildtitle}' COLLATE NOCASE
          OR EXISTS (
              SELECT 1 FROM json_each(aliases)
              WHERE json_each.value = '#{wildtitle}' COLLATE NOCASE
          )
        LIMIT 1;
      SQL
      db.execute(query_struct) do |row|
        full_data = JSON.parse(row[2])
        if wildtitle.downcase == row[0].downcase
          full_data["SAliases"] = JSON.parse(row[1])
          full_data["Structure"] = optimized
          puts JSON.pretty_generate(full_data)
          dump_to_db(db, full_data)
          FileUtils.cp(svg_path, "/home/xea/jsonfsstructure")
          FileUtils.rm(svg_path)
        else
          #for salt in full_data["FullSalts"]
          #  next if wildtitle.downcase != salt.downcase
          #  full_data["SAliases"] = JSON.parse(row[1])
          #  full_data["SaltStructure"] = [] if full_data["SaltStructure"] == nil
          #  full_data["SaltStructuresBase64"] += [ encoded_svg ]
          #  puts JSON.pretty_generate(full_data)
          #  #dump_to_db(db, full_data)
          #  FileUtils.cp(svg_path, "/home/xea/jsonfsstructure")
          #end
        end
      end
    rescue => e
      puts "An error occurred with file #{svg_path}: #{e.message}"
    end
  end
  Dir.glob('substance/*').each do |file_path|
    begin
      title = Pathname(file_path).basename.to_s
      mw = ""
      abr = ""
      full_data = nil
      if File.exist?("#{file_path}/mods.json")
        mods_file_content = File.read("#{file_path}/mods.json")
        mods_data = JSON.parse(mods_file_content)
        if mods_data != nil
          full_data = mods_data
        end
        if mods_data['Title'] != nil
          title = mods_data['Title']
        end
        if mods_data['MolecularWeight'] != nil
          mw = mods_data['MolecularWeight']
        end
        if mods_data['Abbreviation'] != nil
          abr = mods_data['Abbreviation']
        end
      end
      if File.exist?("#{file_path}/vars.json")
        vars_file_content = File.read("#{file_path}/vars.json")
        vars_data = JSON.parse(vars_file_content)
        if vars_data != nil
          if full_data != nil
            full_data = full_data.merge(vars_data)
          else
            full_data = vars_data
          end
        end
        if vars_data['Title'] != nil
          title = vars_data['Title']
        end
        if vars_data['MolecularWeight'] != nil
          mw = vars_data['MolecularWeight']
        end
        if vars_data['Abbreviation'] != nil
          abr = vars_data['Abbreviation']
        end
      end
      if full_data
        puts JSON.pretty_generate(full_data)
        dump_to_db(db, full_data)
        FileUtils.cp_r(file_path, "/home/xea/jsonfs")
        FileUtils.rm_r(file_path)
        puts "cp " + file_path + "/home/xea/jsonfs"
      end

      #if mods_data != nil && mods_data.key?('ChemicalClasses') && mods_data['ChemicalClasses'].include?(iclass.downcase)
      if mods_data != nil && mods_data[vclass] != nil && mods_data[vclass].include?(iclass.downcase)
        puts vclass
        if mods_data['IsClass'] != true && mods_data[vclass].include?(iclass)
            index_substances << { "Title": title, "MW": mw }
            return nil
        end
        if index['First'].is_a?(String)
          fstr = index['First']
          index['First'] = {}
          index['First']['Title'] = fstr
        end
        if title != nil
          index['First']['Title'] = title
        end
        if abr != nil
          index['First']['Abr'] = abr
        end
        if mw != nil
          index['First']['MW'] = mw
        end
        #for par in mods_data['ChemicalClasses'].drop(1)
        for par in mods_data[vclass].drop(1)
          par_file_content = File.read("#{pclass}/#{par}.json")
          par_data = JSON.parse(par_file_content)
          if par_data['Children'] != nil
            if !par_data['Children'].include?(iclass.downcase)
              par_data['Children'] += [ iclass.downcase ]
            end
          else
            par_data['Children'] = [ iclass.downcase ]
          end
          File.write("#{pclass}/#{par}.json", JSON.pretty_generate(par_data))
        end
      end
      #if vars_data != nil && vars_data['ChemicalClasses'] && vars_data['ChemicalClasses'].include?(iclass.downcase)
      if vars_data != nil && vars_data[vclass] != nil && vars_data[vclass].include?(iclass.downcase)
        if vars_data['IsClass'] != true && vars_data[vclass].include?(iclass)
          index_substances << { "Title": title, "MW": mw }
          return nil
        end
        if index['First'].is_a?(String)
          fstr = index['First']
          index['First'] = {}
          index['First']['Title'] = fstr
        end
        if title != nil
          index['First']['Title'] = title
        end
        if abr != nil
          index['First']['Abr'] = abr
        end
        if mw != nil
          index['First']['MW'] = mw
        end
        #for par in mods_data['ChemicalClasses'].drop(1)
        for par in mods_data[vclass].drop(1)
          par_file_content = File.read("#{pclass}/#{par}.json")
          par_data = JSON.parse(par_file_content)
          if par_data['Children']
            if !par_data['Children'].include?(iclass.downcase)
              par_data['Children'] += [ iclass.downcase ]
            end
          else
            par_data['Children'] = [ iclass.downcase ]
          end
          File.write("#{pclass}/#{par}.json", JSON.pretty_generate(par_data))
        end
      end

    rescue => e
      puts "An error occurred with file #{file_path}: #{e.message}"
    end
  end

  index['Entries'] = index_substances
  File.write("#{pclass}/#{iclass.downcase}.json", JSON.pretty_generate(index))

  puts JSON.pretty_generate(index)
end
