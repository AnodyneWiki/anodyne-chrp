require 'fileutils'
require 'sqlite3'
require 'open3'
require 'json'

require_relative 'config'
require_relative 'structure'
require_relative 'stereoisomers'
require_relative 'forms'
require_relative 'text'
require_relative 'refs'
require_relative 'effects'
require_relative 'sql'

require_relative 'chemspider'
require_relative 'dosing'
require_relative 'erowid'
require_relative 'unii'
require_relative 'hmdb'
require_relative 'pubchem'
require_relative 'wikipedia'
require_relative 'sciencemadness'
require_relative 'swisstargetprediction'
require_relative 'stereoisomers'
require_relative 'sitemap'
require_relative 'dbi-igs'
require_relative 'kegg'
require_relative 'mesh'

PHARM = [
  "Human Drugs", "Drug Indication", "Drug Classes", "Clinical Trials", "Therapeutic Uses", "Drug Warnings", "Reported Fatal Dose", "Pharmacodynamics", "MeSH Pharmacological Classification", "FDA Pharmacological Classification", "Pharmacological Classes", "ATC Code"
]

def try(root, compound, prefixes, postfix, unii, key, indepth, salt)
  record = Hash.new
  record['UNII'] = unii if unii != nil
  record['Abbreviation'] = root["Abbreviation"] if root["Abbreviation"] != nil and root["Abbreviation"].is_a?(Array)
  record['PubChemId'] = compound[3..] if compound != nil and compound.start_with?("CID")
  record['Formating'] = []

  if prefixes != nil
    for prefix in prefixes
      pretit = "#{prefix}#{root["Title"]}"
      record.merge!(query_pubchem(record, pretit, !(key == "racemic" && !salt && indepth)))
      next if record["PubChemId"] == nil
      record['Title'] = pretit
      break
    end
  elsif postfix != nil
    pretit = "#{root["Title"]}#{postfix}"
    record.merge!(query_pubchem(record, pretit, true))
    return record if record["PubChemId"] == nil
    record['Title'] = pretit
  else
    record.merge!(query_pubchem(record, root["Title"], true))
  end

  return record if record["PubChemId"] == nil && record["Title"] == nil && record["UNII"] == nil
  
  record.merge!(query_unii(root, record, true, nil, nil)) if record['UNII'] != nil

  if indepth
    #record = record.merge(query_chemspider(record, compound))
    #record = record.merge(query_swtp(record))

    record.merge!(query_hmdb record) if record["HMDB ID"] != nil
    record.merge!(query_wikipedia record)
    record.merge!(query_sciencemadness record)
    record.merge!(query_dosing record)
    #record.merge!(query_kegg record)
    record.merge!(query_mesh record)
    #record.merge!(query_experiences record)
    record.merge!(query_dbi_igs record)
  end

  mpca = ""
  mpca += " -f#{record["MolpicFlip"]}" if record["MolpicFlip"]
  mpca += " -r#{record["MolpicRotation"]}" if record["MolpicRotation"]

  if !salt
    record.merge!(generate_structure(record, mpca, true))
    root["Structure"] = record["Structure"] if key == "racemic" && record["Structure"] && indepth
    record["References"] = generate_references(record)
  end

  if contains_symbols(record["Title"])
    raw_t = replace_symbols(record["Title"].downcase)
    record["Formating"] += [ raw_t ]
  end
  return record
end

def query(ssub, ltitle, dtitle, sstitle, rrtitle, srtitle, rstitle)
  return record if ssub["Title"] == nil
  db = SQLite3::Database.new 'db.sqlite'
  db.execute <<-SQL
    CREATE TABLE IF NOT EXISTS substances (
      id INTEGER PRIMARY KEY,
      title TEXT UNIQUE,
      aliases TEXT,
      data_json TEXT
    );
  SQL
  db.execute <<-SQL
    CREATE TABLE IF NOT EXISTS proteins (
      id INTEGER PRIMARY KEY,
      title TEXT UNIQUE,
      aliases TEXT,
      data_json TEXT
    );
  SQL

  record = Hash.new
  record["Title"] = ssub["Title"]
  record["Abbreviation"] = ssub["Abrs"] if ssub["Abrs"] != nil
  record["Formating"] = []
  record["References"] = []
  record["Refs"] = []
  record["RefCount"] = 1
  record["Salts"] = []
  record["SaltData"] = []
  record["Esters"] = []
  record["Esters"] = ssub["Esters"] if ssub["Esters"] != nil
  record["Stereoisomers"] = Array.new
  record["StereoisomerData"] = Array.new
  record["Actives"] = ssub["Actives"] if ssub["Actives"] != nil
  #record["MolpicFlip"] = "1" if flipx == true

  #query_struct = <<-SQL
  #  SELECT title, aliases, data_json
  #  FROM substances
  #  WHERE title = ? COLLATE NOCASE
  #    OR EXISTS (
  #        SELECT 1 FROM json_each(aliases)
  #        WHERE json_each.value = ? COLLATE NOCASE
  #    )
  #  LIMIT 1;
  #SQL
  #od_title = nil
  #od_record = {}
  #db.execute(query_struct, [title, title]) do |row|
  #  od_title = row[0]
  #  od_record = JSON.parse(row[2])
  #end

  key = "racemic"
  record.merge!(try(record, ssub["Search"], [CHIRAL_PREFIXES[key][:prefered]], nil, record["UNII"], key, true, false))
  return record if record["Title"] == nil

  #CHIRAL_PREFIXES.each do |key, value|
  #  next if key == "dexter" || key == "laevus" || key == "logical-racemic" || key == "meso"  || key == "racemic"
  #  puts "Searching for (Stereoisomer): #{key}"
  #  if key == "racemic"
  #  elsif key == "left-handed" && (record["Chirality"] == nil || (record["Chirality"] != "achiral" && record["Chirality"] != "absolute"))
  #    ltitle = "#{CHIRAL_PREFIXES[key][:prefered]}#{ssub["Title"]}" if ltitle == nil
  #    levo = Hash.new
  #    levo.merge!(try(levo, ltitle, [CHIRAL_PREFIXES[key][:prefered]], nil, nil, key, false, false))
  #    levo["Title"] = ltitle
  #    record["Stereoisomers"] << ltitle
  #    next if levo["PubChemId"] == nil
  #    record["StereoisomerData"].push(levo)
  #  elsif key == "right-handed" && (record["Chirality"] == nil || (record["Chirality"] != "achiral" && record["Chirality"] != "absolute"))
  #    dtitle = "#{CHIRAL_PREFIXES[key][:prefered]}#{ssub["Title"]}" if dtitle == nil
  #    dextro = Hash.new
  #    dextro.merge!(try(dextro, dtitle, [CHIRAL_PREFIXES[key][:prefered]], nil, nil, key, false, false))
  #    dtitle = dextro["Title"] if dtitle == nil or dtitle.empty?
  #    record["Stereoisomers"].push(dtitle)
  #    next if dextro["PubChemId"] == nil
  #    record["StereoisomerData"].push(dextro)
  #  end
  #end

  record.merge!(generate_structure(record, "", true))
  check = false
  if record["StereoisomerData"] == nil || record["StereoisomerData"].size == 0
    check = true
  else
    pubchem = [ record["PubChemId"] ]
    smiles = [ record["SMILES"] ]
    for cst in record["StereoisomerData"]
      if pubchem.include?(cst["PubChemId"]) || smiles.include?(cst["SMILES"]) 
        check = true
      end
      smiles << cst["SMILES"]
      pubchem << cst["PubChemId"]
    end
  end
  if record["SMILES"] != nil && (record["Chirality"] == nil || (record["Chirality"] != "achiral" && record["Chirality"] != "absolute"))
    if check == true 
      record["Stereoisomers"] = []
      record["StereoisomerData"] = []
    end
    pre_stereoisomers = list_stereoisomers(record["SMILES"])
    if pre_stereoisomers.size == 1
      puts "No chiral centers found"
      record["Chirality"] = "achiral"
    elsif pre_stereoisomers.size == 2
      record["Chirality"] = "racemic"
      record["StereoisomerType"] = "enantiomer"
      puts "enantiomer"
      for ster in 0..pre_stereoisomers.size
        rec = nil
        id = ster
        found = false
        next if pre_stereoisomers[ster] == nil
        #if record["StereoisomerData"] != nil and not record["StereoisomerData"].empty?
        #  for data in 0..record["StereoisomerData"].size
        #    next if record["StereoisomerData"][data] == nil
        #    if ster == 0 and (record["StereoisomerData"][data]["Title"].start_with?("(S)-") or record["StereoisomerData"][data]["Title"] == dtitle)
        #      rec = record["StereoisomerData"][data]
        #      id = data
        #      found = true
        #    end
        #    if ster == 1 and (record["StereoisomerData"][data]["Title"].start_with?("(R)-") or record["StereoisomerData"][data]["Title"].start_with?(ltitle))
        #      rec = record["StereoisomerData"][data]
        #      id = data
        #      found = true
        #    end
        #  end
        #end
        #next if found == true

        rec = Hash.new if rec == nil
        rec["Title"] = pre_stereoisomers[ster][0] + record["Title"] if rec["Title"] == nil
        rec["Title"] = ltitle if ster == 0 and ltitle != nil
        rec["Title"] = dtitle if ster == 1 and dtitle != nil
        #next if record["StereoisomerData"][ster] != nil && record["StereoisomerData"][ster]["Title"] == rec["Title"]
        rec["SMILES"] = pre_stereoisomers[ster][1]

        #next if record["StereoisomerData"][ster] != nil && record["StereoisomerData"][ster]["Title"] == rec["Title"]
        rec.merge!(generate_structure(rec, "", true))
        record["Stereoisomers"][ster] = rec["Title"] # #
        record["StereoisomerData"][ster] = rec # #
      end
    elsif pre_stereoisomers.size == 4
      record["Chirality"] = "racemic"
      record["StereoisomerType"] = "diastereomer"
      for ster in 0...pre_stereoisomers.size
        rec = Hash.new
        rec["Title"] = pre_stereoisomers[ster][0] + record["Title"]
        next if record["Stereoisomers"].include?(rec["Title"])
        rec["SMILES"] = pre_stereoisomers[ster][1]
        rec["Title"] = sstitle if sstitle != nil && rec["Title"].start_with?("(1S,2S)-")
        rec["Title"] = rstitle if rstitle != nil && rec["Title"].start_with?("(1R,2S)-")
        rec["Title"] = rrtitle if rrtitle != nil && rec["Title"].start_with?("(1R,2R)-")
        rec["Title"] = srtitle if srtitle != nil && rec["Title"].start_with?("(1S,2R)-")
        rec.merge!(generate_structure(rec, "", false))
        record["Stereoisomers"] << rec["Title"]
        record["StereoisomerData"] << rec
      end
    else
      puts "Uncommon amount of stereoisomers: #{pre_stereoisomers.size}"
      for st in pre_stereoisomers
        puts st
      end
    end
  end

  for salt in 0...record["SaltData"].length
    s_record = Hash.new
    s_record["IsSalt"] = true
    s_record["SaltSMILES"] = record["SMILES"].dup
    s_record["SMILES"] = record["SMILES"].dup
    s_record["SaltFormula"] = record["SaltData"][salt]["Formula"].dup
    s_record["HeavyAtomCount"] = record["HeavyAtomCount"].dup
    s_record["SaltAmineCount"] = record["SaltData"][salt]["AmineCount"].dup
    s_record["SaltAcidCount"] = record["SaltData"][salt]["AcidCount"].dup
    ##s_record["Name"] = "#{count_prefix(s_record["SaltAcidCount"])}#{record["SaltData"][salt]["Name"].downcase}"
    s_record["Title"] = record["SaltData"][salt]["Title"].dup
    #s_record.merge!(try(record, s_record["Title"], compound, nil, " #{record["SaltData"][salt]["Name"]}", record["SaltData"][salt]["UNII"], "racemic", false, true))
    s_record.merge!(generate_structure(s_record, "", false))

    if s_record["Structure"] == nil
      record["SaltData"].delete(salt)
      next
    else
      record["SaltData"][salt]["Structure"] = s_record["Structure"]
    end
  end

  ##for fster in record["StereoisomerData"]
  ##  record["StereoisomerData"] += [ { Title: fster["Title"].dup, Aliases: fster["Aliases"].dup, Structure: fster["Structure"].dup, SMILES: fster["SMILES"].dup, PubChemId: fster["PubChemId"].dup, UNII: fster["UNII"].dup} ]
  ##end
  #record["References"] = generate_references(record)

  #for estruct in record["EsterStructs"]
  #  es_record = {}
  #  es_record["IsEster"] = true
  #  es_record = es_record.merge(query_pubchem(es_record, "#{title} #{ester}", "#{nc} #{ester}", true))
  #  #tmp_record["Title"] = "#{nc} #{ester}" if tmp_record["Title"] == nil
  #  puts "Fetching Form (Ester): #{ester}"
  #  record["Esters"] += [ ester ]
  #  #tmp_record["EsterStruct"]["Title"] = "#{record["Title"]} #{ester}"
  #  #  tmp_record["EsterStruct"]["Name"] = ester
  #  #  ester_records += [ tmp_record ]
  #end
  #CHIRAL_PREFIXES.each do |key, value|
  #  if key != "racemic" && (((record["ChemicalClasses"] != nil && record["ChemicalClasses"].include?("amino acid")) || (key != "logical-racemic" && key != "dexter" && key != "laevus")) && ((record["ChemicalClasses"] == nil || !record["ChemicalClasses"].include?("amino acid")) || (key != "left-handed" && key != "right-handed"))) && record["Chirality"] != "absolute"
  #    for prefix in value[:prefixes]
  #      tmp_record = {}
  #      if record["Wikipedia"] != nil
  #        tmp_record["OldWikipedia"] = record["Wikipedia"]
  #      end
  #      tmp_record = query_pubchem(tmp_record, value[:prefered] + record["Title"], prefix + nc, true)
  #      tmp_record = tmp_record.reject { |k, v| record[k] == v }
  #      tmp_record["References"] = generate_references(tmp_record)
  #      if tmp_record["Title"] != nil && tmp_record["PubChemId"] != record["PubChemId"]
  #        puts "Fetching Form (Stereoisomer): #{key}"
  #        record["Stereoisomers"] += [ tmp_record["Title"] ]
  #        tmp_record["StereoStructCount"] = record["StereoStructCount"]
  #        record["StereoStructCount"] += 1
  #        record["StereoStructs"][tmp_record["StereoStructCount"]]["Name"] = value[:prefered]
  #        record["StereoStructs"][tmp_record["StereoStructCount"]]["Title"] = tmp_record["Title"]
  #        record["StereoStructs"][tmp_record["StereoStructCount"]]["UNII"] = tmp_record["UNII"] if tmp_record["UNII"] != nil
  #        record["StereoStructs"][tmp_record["StereoStructCount"]]["Chirality"] = key#tmp_record["Chirality"] if tmp_record["Chirality"] != nil
  #        #tmp_record["StereoSearch"] = prefix + nc
  #        next if tmp_record["UNII"] == nil

  #        tmp_record = query_unii(tmp_record, true, nil, nil)
  #        if tmp_record["Salts"] != nil
  #          record["Salts"] += tmp_record["Salts"]
  #          record["Salts"] = record["Salts"].uniq
  #        end
  #        stereo_records += [ tmp_record ]
  #        break if key == "vague"
  #      end
  #    end
  #  end
  #end

  for stereo in record["StereoisomerData"]
    next if stereo["References"] == nil

    for st_ref in stereo["References"]
      for ref_it in 0...record["References"].length
        next if st_ref[:Name] != record["References"][ref_it][:Name]
        for url in st_ref[:Urls]
          url[:Name] = stereo["Title"]
          url[:Sub] = true
          record["References"][ref_it][:Urls] += [ url ]
        end
      end
    end
  end

  if record["ChemicalClasses"]
    for subst in record["ChemicalClasses"]
      subst_file = "substituted/#{subst.downcase.gsub(/\s+/, '_')}.json"
      if File.exist?(subst_file)
        json_text = File.read(subst_file)
        next if json_text == nil
        json_content = JSON.parse(json_text)
        if json_content != nil && json_content["Entries"] != nil
          eset = false
          for entr in json_content["Entries"]
            if entr["Title"].downcase == record["Title"].downcase
              entr["Abr"] = record["Abbreviation"]
              entr["MW"] = record["MolecularWeight"]
              eset = true
              break
            end
          end
          if json_content["First"] != nil && json_content["First"]["Title"] != nil
            if json_content["First"]["Title"].downcase == record["Title"].downcase
              json_content["First"]["Title"] = record["Title"]
              json_content["First"]["Abr"] = record["Abbreviation"]
              json_content["First"]["MW"] = record["MolecularWeight"]
              eset = true
            end
          end
          json_content["Entries"] += [ { "Title": record["Title"], "Abr": record["Abbreviation"], "MW": record["MolecularWeight"] } ] if eset == false
          File.write(subst_file, JSON.pretty_generate(json_content))
        end
      end
    end
  end

  if ssub["Classes"] != nil || record['Classes'] != nil
    record['Classes'] = [] if record['Classes'] == nil
    record['Classes'] = ssub["Classes"] if ssub["Classes"] != nil
    record["Subjective Effects"] = get_effects(record['Classes'])
  end

  record.merge!(query_kegg record)

  dump_to_db(db, record)
  #generate_sitemap(db)
  return record

  #for struct in 0...record["SaltStructs"].length
  #  sa_record = {}
  #  next if record["Salts"].include?(record["SaltStructs"][struct]["Name"])
  #  record["Salts"] += [ record["SaltStructs"][struct]["Name"] ]
  #  sa_record["IsSalt"] = true
  #  sa_record["SMILES"] = record["SMILES"]
  #  sa_record["HeavyAtomCount"] = record["HeavyAtomCount"]
  #  sa_record["Title"] = record["SaltStructs"][struct]["Title"]
  #  #struct["Formula"] = SALTS[record["SaltStructs"][salt]["Name"]][:formula]
  #  sa_record = sa_record.merge(query_pubchem(sa_record, sa_record["Title"], nc + " #{record['SaltStructs'][struct]['Name']}", true))
  #  record["SaltStructs"][struct]["StructureRaw"] = generate_structure(sa_record, record["SaltStructs"][struct], mpca, false)
  #end
  #for ester in ester_records
  #  next if ester["Title"] == nil
  #  FileUtils.mkdir_p("substance/#{ester['Title'].downcase.gsub(/\s+/, '_')}")
  #  File.write("substance/#{ester['Title'].downcase.gsub(/\s+/, '_')}/vars.json", JSON.pretty_generate({ SubstanceRedirectSource: ester['Title'], SubstanceRedirect: "#{record['Title'].downcase.gsub(/\s+/, '_')}", SubstanceRedirectAnchor: "Chemistry" }))
  #  ester["EsterStruct"]["StructureRaw"] = generate_structure(ester, nil, mpca, false)
  #  ester["EsterStructCount"] = record["EsterStructsCount"]
  #  record["EsterStructsCount"] += 1
  #  record["EsterStructs"][ester["EsterStructCount"]] = ester["EsterStruct"]
  #  record["EsterStructs"][ester["EsterStructCount"]]["Structure"] = ester["Structure"] if ester["Structure"]
  #end

  #puts "substance/#{title.downcase.gsub(/\s+/, '_')}"
  #FileUtils.mkdir_p("substance/#{title.downcase.gsub(/\s+/, '_')}")
  #File.write("substance/#{title.downcase.gsub(/\s+/, '_')}/vars.json", JSON.pretty_generate(record))
end

def query_composite(ssub)
  return record if ssub["Title"] == nil
  db = SQLite3::Database.new 'db.sqlite'
  db.execute <<-SQL
    CREATE TABLE IF NOT EXISTS composites (
      id INTEGER PRIMARY KEY,
      title TEXT UNIQUE,
      aliases TEXT,
      substances TEXT,
      data_json TEXT
    );
  SQL


  record = Hash.new
  record["Title"] = ssub["Title"]
  record["Substances"] = ssub["Substances"]
  record["Abbreviation"] = ssub["Abrs"] if ssub["Abrs"] != nil
  record["Formating"] = []
  record["References"] = []
  record["Refs"] = []
  record["RefCount"] = 1

  #query_struct = <<-SQL
  #  SELECT title, aliases, data_json
  #  FROM substances
  #  WHERE title = ? COLLATE NOCASE
  #    OR EXISTS (
  #        SELECT 1 FROM json_each(aliases)
  #        WHERE json_each.value = ? COLLATE NOCASE
  #    )
  #  LIMIT 1;
  #SQL
  #od_title = nil
  #od_record = {}
  #db.execute(query_struct, [title, title]) do |row|
  #  od_title = row[0]
  #  od_record = JSON.parse(row[2])
  #end

  #record.merge!(ssub)
  puts "Querying composite: #{record['Title']}"
  dump_to_db_composite(db, record)
  return record
end
