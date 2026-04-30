require 'json'
require 'sqlite3'

def dump_to_db(db, record)
  #puts (JSON.pretty_generate record)
  return if record["Title"] == nil
  abrs = []
  if record["SAliases"]
    abrs = record["SAliases"]
    record.delete("SAliases")
  end
  abrs.push(record["Abbreviation"]) if record["Abbreviation"] != nil and not record["Abbreviation"].empty?
  abrs.push(record["Formating"]) if record["Formating"]
  abrs.push(record["Aliases"]) if record["Aliases"]
  abrs.push(record["FullSalts"]) if record["FullSalts"]
  abrs.push(record["StereoisomersUNII"]) if record["StereoisomersUNII"]
  abrs.push(record["SaltsUNII"]) if record["SaltsUNII"]
  abrs.push(record["Stereoisomers"]) if record["Stereoisomers"]
  abrs.push(record["Slang"]) if record["Slang"]
  abrs.push(record["MolecularFormula"].gsub("<sub>", "").gsub("</sub>", "")) if record["MolecularFormula"] != nil
  if record["StereoTitles"] != nil
    for stereotitle in record["StereoTitles"]
      abrs.push(stereotitle["Title"])
    end
  end
  appn = [ record["UNII"], record["StereoisomerRacemic"], record["SMILES"], "CID#{record["PubChemId"]}", record["InChI"], record["InChIKey"], record["IUPACName"], record["CAS"], record["Wikidata"], record["European.Community.(EC).Number"], record["HMDB.ID"], record["ChEMBL"], record["ChEBI"], record["EINECS"] ]

  clean_record = record.dup
  clean_record = clean_record.reject{ |_, v| v.respond_to?(:empty?) ? v.empty? : v.nil? }

  for str in appn
    abrs << str if str != nil
  end
  abrs = abrs.compact.uniq
  record.delete("HMDB Metabolite")
  puts "INSERT INTO substances (#{record["Title"]})"
  db.execute("INSERT OR REPLACE INTO substances (title, aliases, data_json) VALUES (?, ?, ?)",
             [record["Title"], abrs.to_json, record.to_json])
end

def dump_to_db_composite(db, record)
  #puts (JSON.pretty_generate record)
  return if record["Title"] == nil
  abrs = []
  if record["SAliases"]
    abrs = record["SAliases"]
    record.delete("SAliases")
  end
  abrs.push(record["Abbreviation"]) if record["Abbreviation"] != nil and not record["Abbreviation"].empty?
  abrs.push(record["Formating"]) if record["Formating"]
  abrs.push(record["Aliases"]) if record["Aliases"]
  abrs.push(record["Slang"]) if record["Slang"]

  clean_record = record.dup
  clean_record = clean_record.reject{ |_, v| v.respond_to?(:empty?) ? v.empty? : v.nil? }

  abrs = abrs.compact.uniq
  puts "INSERT INTO composites (#{record["Title"]})"
  db.execute("INSERT OR REPLACE INTO composites (title, aliases, substances, data_json) VALUES (?, ?, ?, ?)",
             [record["Title"], abrs.to_json, record["Substances"].to_json, record.to_json])
end
