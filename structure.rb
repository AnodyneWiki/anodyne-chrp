require 'open3'

require_relative 'config'
require_relative 'forms'

def generate_structure(record, mpca, subst)
  mpc = "java -jar molpic/molpic.jar " + mpca
  title = record["Title"]
  title = record["SaltTitle"] if record["SaltTitle"] != nil
  return record if title == nil
  return record if record["SMILES"] == nil
  smiles = record["SMILES"]
  
  only_subst = false
  ENV["DISPLAY"] = ""
  if record["IsSalt"]
    if record["SaltFormula"] != ""
      smiles = record["SaltSMILES"]
      atoms = ""
      if record["SaltAmineCount"] > 1
        for at in 0...record["HeavyAtomCount"]
          if at == 0
            atoms += at.to_s
          else
            atoms += ",#{at.to_s}"
          end
        end
        atoms = " |Sg:n:#{atoms}:#{record["SaltAmineCount"]}:ht|"
      end
      mpc += " -m \"#{smiles}#{atoms}\" -s \"#{record["SaltFormula"]}\" -ac \"#{record["SaltAcidCount"]}\"" #-u #{record[\"SaltAmineCount\"]}"
    end
  else
    mpc += " -m \"#{record["SMILES"]}\""
  end

  cffj = nil
  if !$options[:c].nil?
    cff = $options[:c] + "/" + Digest::MD5.hexdigest(mpc) + ".svg"
    if subst
      cffj = $options[:c] + "/" + Digest::MD5.hexdigest(mpc) + ".json"
      mpc += " -d \"#{cffj}\""
    end
    if File.exist?(cff) && File.size(cff) > 0 && ((Time.now - File.mtime(cff)) / (24 * 60 * 60)) < 1.0 #&& (scffc)
      if $options[:v]
        puts "Loading Cache: " + cff
      end
      if subst
        if File.exist?(cffj) && File.size(cffj) > 0
          json_file = File.read(cffj)
          json_data = JSON.parse(json_file)
          if json_data['ChemicalClasses'] != nil
            record['ChemicalClasses'] = json_data['ChemicalClasses']
          end
        else
          #only_subst = true
          #mpc += " -s"
        end
      end
    end
    mpc += " -o \"#{cff}\""
  else
    mpc += " -o \"structure/#{title.downcase.gsub(/\s+/, '_')}.svg\""
    if subst
      cffj = "/tmp/molpic_" + Digest::MD5.hexdigest(mpc) + ".json"
      mpc += " -d \"#{cffj}\""
    end
    #mpc += " -j \"#{vars_file}\""
  end

  puts "#{mpc}" if !$options[:v].nil?
  ret = system(mpc)

  if !ret
    return record
  end
  svg_file = File.read( (!$options[:c].nil? && cff != nil) ? cff : "structure/#{title.downcase.gsub(/\s+/, '_')}.svg")
  json_file = File.read(cffj) if cffj != nil
  if !$options[:c].nil?
    FileUtils.cp(cff, "structure/#{title.downcase.gsub(/\s+/, '_')}.svg")
  end
  if subst && json_file != nil
    json_data = JSON.parse(json_file)
    if json_data['classes'] != nil
      if record['ChemicalClasses'] == nil
        record['ChemicalClasses'] = []
      end
      record['ChemicalClasses'] += json_data['classes']
    end
  end
  #puts svg_file
  log = "Generating Structure: #{title.downcase.gsub(/\s+/, '_')}.svg"
  optimized = optimize_svg(svg_with_white_background(svg_file))
  record["Structure"] = optimized
  if subst
    log += " (Substitutions:"
    if record['ChemicalClasses']
      record['ChemicalClasses'] = record['ChemicalClasses'].uniq
      for isubst in record['ChemicalClasses']
        if isubst == "amino acid"
          record["ChiralityAminoAcid"] = true
        end
        if isubst != record["ChemicalClasses"][0]
          log += ", "
        else
          log += " "
        end
        log += isubst
      end
      log += ")"
    end
  end
  return record
end
