require 'json'
require 'date'

require_relative 'config'
require_relative 'fetch'
require_relative 'forms'
require_relative 'icons'
require_relative 'text'
require_relative 'refs'

PUBCHEM_URL = "https://pubchem.ncbi.nlm.nih.gov/"
PUG_REST = PUBCHEM_URL + "rest/pug"
PUG_VIEW = PUBCHEM_URL + "rest/pug_view"

MAX_SYMS = 25
REST_PROPS = [
  "Title",
  "MolecularFormula",
  "MolecularWeight",
  "SMILES",
  "InChI",
  "InChIKey",
  "IUPACName",
  "XLogP",
  "HeavyAtomCount"
]
VIEW_PROPS = [
  "CAS",
  "European Community (EC) Number",
  "UNII",
  "DrugBank ID",
  "DSSTox Substance ID",
  "HMDB ID",
  "KEGG ID",
  "Wikidata",
  "Wikipedia",
  "Physical Description",
  "Color/Form",
  "Odor",
  "Taste",
  "Density",
  "Melting Point",
  "Boiling Point",
  "Flash Point",
  "Solubility",
  "Stability/Shelf Life",
  "Decomposition",
  "pH",
  "Human Drugs",
  "Drug Indication",
  "Drug Classes",
  "Clinical Trials",
  "Therapeutic Uses",
  "Drug Warnings",
  "Reported Fatal Dose",
  "Toxicity",
  "Toxicity Data",
  "Human Toxicity Values",
  "Non-Human Toxicity Values",
  "Ecotoxicity Values",
  "Health Effects",
  "Adverse Effects",
  "Acute Effects",
  "Treatment",
  "Interactions",
  "Associated Disorders and Diseases",
  "Interactions and Pathways",
  "Chemical Classes",
  "Pharmacodynamics",
  "MeSH Pharmacological Classification",
  "FDA Pharmacological Classification",
  "Pharmacological Classes",
  "ATC Code",
  "ATCvet Code",
  "Absorption, Distribution and Excretion",
  "Metabolism/Metabolites",
  "Biological Half-Life",
  "Mechanism of Action",
  "Impurities"
]
VIEW_L_PROPS = [
  "ATC Code",
  "ATCvet Code"
]
VIEW_A_PROPS = [
  "MeSH Pharmacological Classification",
  "FDA Pharmacological Classification",
]
  #if !json_content.include?("xml")
  #  json_props = JSON.parse(json_content)
  #  if !json_props["Fault"]
  #    properties = json_props["PropertyTable"]["Properties"][0]
  #    for prop in REST_PROPS
  #      record[prop] = properties[prop]
  #    end
  #    record["PubChemId"] = properties["CID"]
  #    #record["Title"] = title
  #  end
  #end

#def generate_substitutions()
#  for subst in $subst_classes
#    url = PUG_REST + "/compound/name/#{subst[:key]}/property/title,complexity/JSON"
#    json_props = JSON.parse(fetch(url, "application/json"))
#    properties = json_props["PropertyTable"]["Properties"][0]
#    subst["CID"] = properties["CID"]
#    subst["Complexity"] = properties["Complexity"]
#  end
#  File.write('substitutions.json', JSON.pretty_generate($subst_classes))
#end

#def load_substitutions()
#  file_content = File.read('substitutions.json')
#  if file_content != nil
#    $subst_classes = JSON.parse(file_content)
#  else
#    generate_substitutions()
#  end
#end
def fetch_interactions(record)
  return
end
def html_formula(formula)
  pattern = /([A-Z][a-z]*)(\d*)/
  
  html_formula = formula.gsub(pattern) do |match|
    element, number = $1, $2
    
    if number.empty?
      "#{element}"
    else
      "#{element}<sub>#{number}</sub>"
    end
  end
  html_formula
end

def recurse_section(record, compound, json_obj)
  # prop iteration
  prop_set = 0
  for prop in VIEW_PROPS
    next if record[prop] != nil || json_obj["TOCHeading"] != prop || json_obj["Information"] == nil

    strs = Array.new #if record[prop] == nil
    #puts json_obj["TOCHeading"]
    json_obj["Information"].each do |info|
      next if info["Value"] == nil

      if prop == "MeSH Pharmacological Classification"
        hdr = record["MeSH Headers"].select { |h| h["Ref"] == info["ReferenceNumber"] }.map do |obj|
          {
            "Name" => obj["Name"].dup.delete_suffix('s'),
            "Id"   => obj["Id"].dup || nil,
            "Ref"  => obj["Ref"].dup || nil,
            "Link" => obj["Link"].dup || nil
          }
        end
        strs << hdr[0]
      elsif VIEW_A_PROPS.include?(prop)
        strs << info
      elsif info["Value"]["StringWithMarkup"] != nil
        info["Value"]["StringWithMarkup"].each do |stringwm|
          strs << stringwm["String"]
        end
      end

      next if strs.empty?()
      
      record[prop] = (VIEW_A_PROPS.include?(prop)) ? strs : (VIEW_L_PROPS.include?(prop)) ? strs : strs.first
    end
  end
  #for prop in VIEW_A_PROPS
  #  if json_obj["TOCHeading"] == prop && json_obj["Information"] != nil
  #    #puts json_obj["TOCHeading"]
  #    json_obj["Information"].each do |info|
  #      if info["Value"] != nil && info["Value"]["StringWithMarkup"] != nil && record[prop] == nil
  #        strs = Array.new()
  #        info["Value"]["StringWithMarkup"].each do |stringwm|
  #          strs << stringwm["String"]
  #        end
  #        record[prop] = strs
  #      end
  #    end
  #  end
  #end

  if json_obj["Section"] != nil
    #if record["UNII"] != nil
      #record["UNII"] += [ record["UNII"].delete_prefix("UNII-") ]
    #end
    json_obj["Section"].each do |section|
      recurse_section(record, compound, section)
    end
  end
end

def fetch_synonyms(record)
  url = PUG_REST + "/compound/cid/#{record["PubChemId"]}/synonyms/JSON"
  #puts "DEAR GO DNOTEUONHEUTEOU#{url}"
  json_fetch = fetch(url, "application/json")
  return [] if json_fetch == nil
  json_syms = JSON.parse(json_fetch)
  synonyms = json_syms["InformationList"]["Information"][0]["Synonym"]
  filtSynonyms = [ record["PubChemTitle"] ]
  filtSynonyms += synonyms
  unwanted_synonyms = [ record["Title"], record["Title"].upcase, record["PubChemTitle"].upcase, record["Title"].downcase, "#{record["Title"].capitalize()}, DL-", record["CAS"], record["InChIKey"].capitalize(), record["IUPACName"], record["DSSTox Substance ID"], record["Wikidata"], record["Abbreviation"] ] # record["ChemicalClasses"][0]
  unwanted_synonyms += [ record["UNII"] ] if record["UNII"] != nil
  strip_prefixes = [ "U.S.P." ]
  for chir in CHIRAL_PREFIXES
    strip_prefixes += chir[1][:prefixes]
  end
  puts strip_prefixes.inspect
  strip_postfixes = [
    "[WHO-DD]",
    "[USAN]",
    "(ester)",
    "(hydrochloride)",
    " Hydrochloride",
    "(citrate)",
    "(base)",
    "[HSDB]",
    " HCL",
    " HCl",
    " free acid",
    ", Anhydrous",
    " (pharmaceutical)",
    " ratiopharm",
    ", (+/-)-",
    ", cis-(+,-)-",
    " compound",
    ", DL",
    ", dl-"
  ]
  for strip in strip_prefixes
    filtSynonyms = filtSynonyms.map { |str| str.sub(/^#{Regexp.escape(strip)}/, "") }
  end
  for strip in strip_postfixes
    filtSynonyms = filtSynonyms.map { |str| str.sub(/#{Regexp.escape(strip)}$/, "") }
  end
  if record["Abbreviation"] != nil
    if record["Abbreviation"].is_a?(Array)
      for abr in record["Abbreviation"]
        strip_postfixes += [ " (" + abr + ")" ]
      end
    else
      strip_postfixes += [ " (" + record["Abbreviation"] + ")" ]
    end
  end
  refchemSyms = filtSynonyms.select { |str| str.start_with?("RefChem:") }
  if refchemSyms.length != 0
    record["RefChem"] = refchemSyms[0].delete_prefix("RefChem:")
    filtSynonyms = filtSynonyms.reject { |str| str.start_with?("RefChem:") }
  end

  dtxsidSyms = filtSynonyms.select { |str| str.start_with?("DTXSID") }
  if dtxsidSyms.length != 0
    record["DTXSID"] = dtxsidSyms[0].delete_prefix("DTXSID")
    filtSynonyms = filtSynonyms.reject { |str| str.start_with?("DTXSID") }
  end

  uniiSyms = filtSynonyms.select { |str| str.start_with?("UNII-") }
  if uniiSyms.length != 0
    #record[""] = refchemSyms[0].delete_prefix("DTXSID")
    filtSynonyms = filtSynonyms.reject { |str| str.start_with?("UNII-") }
  end
    
  pdSyms = filtSynonyms.select { |str| str.match?(/\APD(?!SP)/) }
  if pdSyms.length != 0
    record["PD"] = pdSyms[0]
    filtSynonyms = filtSynonyms.reject { |str| str.match?(/\APD(?!SP)/) }
  end
  nflisSyms = filtSynonyms.select { |str| str.end_with?("[NFLIS-DRUG]") || str.end_with?("(NFLIS-DRUG)") }
  if nflisSyms.length != 0
    filtSynonyms = filtSynonyms.reject { |str| str.end_with?("[NFLIS-DRUG]") || str.end_with?("(NFLIS-DRUG)") }
    # [NFLIS-DRUG]
  end
  slangSyms = filtSynonyms.select { |str| str.end_with?("[Street Name]") }
  if slangSyms.length != 0
    record["Slang"] = slangSyms.map { |str| str.sub(/#{Regexp.escape("[Street Name]")}$/, "") }
    filtSynonyms = filtSynonyms.reject { |str| str.end_with?("[Street Name]") }
  end
  slangSyms = filtSynonyms.select { |str| str.end_with?("[Street Name]dd") }
  if slangSyms.length != 0
    record["Slang"] += slangSyms.map { |str| str.sub(/#{Regexp.escape("[Street Name]dd")}$/, "") }
    filtSynonyms = filtSynonyms.reject { |str| str.end_with?("[Street Name]dd") }
  end
  filtSynonyms = filtSynonyms.map { |str| str.gsub(/\s*[\[(]INN[^\])]*[\])]\s*$/, '') }
  filtSynonyms = filtSynonyms.map { |str| replace_names(str) }
  filtSynonyms = filtSynonyms.map { |str| (str.length > 10 && str.scan(/[A-Za-z]/).all? { |c| c == c.upcase }) ? str.downcase.sub(/([a-zA-Z])/) { |m| m.upcase } : str }
  filtSynonyms = filtSynonyms.map { |str| str.rstrip }
  filtSynonyms = filtSynonyms.map { |str| str.gsub(/\s\[[^\]]+\]$/, '') }
  filtSynonyms = filtSynonyms.map { |str| str.gsub(/\s\([^\)]+\)$/, '') }
  #if filtSynonyms[0] != nil and filtSynonyms[0] != record["Title"]
  #  record["Title"] = filtSynonyms[0]
  #end
  filtSynonyms = filtSynonyms.uniq
  filtSynonyms = filtSynonyms.reject { |sym| unwanted_synonyms.include?(sym) }
  #filtSynonyms = filtSynonyms - unwanted_synonyms

  # [Street Name] (Street Name)
  # [PMID: 2999404]
  # (1.0mg/ml
  # FREE BASE
  # ChemDiv1_018926
  # CBMicro_005622
  return filtSynonyms
end

def find_mesh_objects(obj, results = [])
  case obj
  when Array
    obj.each { |el| find_mesh_objects(el, results) }
  when Hash
    results << obj if obj['SourceName'] == 'Medical Subject Headings (MeSH)'
    obj.each_value { |v| find_mesh_objects(v, results) }
  end
  results
end

def query_pubchem(record, compound, stereoisomer)
  #load_substitutions()

  compound = record[:Title] if compound.empty? and record[:Title] != nil
  if record["PubChemId"] != nil
    url = PUG_REST + "/compound/cid/#{record["PubChemId"]}/property/"
  elsif compound.start_with?("CID")
    url = PUG_REST + "/compound/cid/#{compound[3..-1]}/property/"
  else
    url = PUG_REST + "/compound/name/#{replace_symbols(compound)}/property/"
  end
  for prop in 0...REST_PROPS.length
    if prop != 0
      url += ","
    end
    url += REST_PROPS[prop]
  end
  url += "/JSON"
  
  json_content = fetch(url, "")
  if json_content == nil
    if !stereoisomer
      puts "failed to query: #{compound}"
    end
    return record
  end
  #if !json_content.include?("xml")
  json_props = JSON.parse(json_content)
  return record if json_props["Fault"] != nil

  properties = json_props["PropertyTable"]["Properties"][0]
  for prop in REST_PROPS
    if prop == "Title"
      record["PubChemTitle"] = properties[prop]
    else
      record[prop] = properties[prop]
    end
  end
  record["PubChemId"] = properties["CID"]
  record["Title"] = compound if record["Title"] == nil
  #end

  return record if record["PubChemId"] == nil

  ##record["Aliases"] = fetch_synonyms(record)

  url = PUG_VIEW + "/data/compound/#{record['PubChemId']}/JSON"
  json_content = fetch(url, "application/json")
  return record if json_content == nil

  json_syms = JSON.parse(json_content)
  sections = json_syms["Record"]["Section"]
  
  if record["MeSH Headers"] == nil
    record["MeSH Headers"] = Array.new if record["MeSH Headers"] == nil

    mesh_objs = find_mesh_objects(json_syms)
    if mesh_objs != nil
      formated = mesh_objs.map do |obj|
        {
          "Name" => obj['Name'].dup,
          "Id"   => obj['SourceID'].dup || nil,
          "Ref"  => obj['ReferenceNumber'].dup || nil,
          "Link" => obj['URL'].dup || nil
        }
      end
      for form in formated
        record["MeSH Headers"] << form
      end
    end
  end

  sections.each do |section|
    recurse_section(record, compound, section)
  end

  #url = PUG_REST + "/compound/cid/#{record['PubChemId']}/description/JSON"
  #json_syms = JSON.parse(fetch(url, "application/json"))
  #infos = json_syms["InformationList"]["Information"]
  #if record["Record Description"] != nil
  #  record["Record Description"] = [ record["Record Description"] ]
  #else
  #  record["Record Description"] = []
  #end
  #for info in infos
  #  if info["Description"] != nil
  #    #record["Record Description"] += [ info["Description"] ]
  #  end
  #end

  if record["MolecularFormula"] != nil
    record["MolecularFormula"] = html_formula(record["MolecularFormula"])
  end
  if record["MolecularWeight"] != nil
    record["MolecularWeight"] = record["MolecularWeight"].sub(/#{Regexp.escape(" Da")}$/, '')
    record["MolecularWeight"] += " g/mol"
  end
  if record["Density"] != nil
    matches = record["Density"].match(/^\d+(\.\d+)?/)
    if matches != nil
      " g/cm<sup>3</sup>"
    end
    record["Density"] += " g/cm<sup>3</sup>"
  end
  if record["Melting Point"] != nil
    match = record["Melting Point"].sub(/^#{Regexp.escape("MP: ")}/, '').match(/^\d+(\.\d+)?\ \°C?/)
    if match != nil
      record["Melting Point"] = match[0]
    end
  end
  if record["Boiling Point"] != nil
    match = record["Boiling Point"].sub(/^#{Regexp.escape("BP: ")}/, '').match(/^\d+(\.\d+)?\ \°C?/)
    if match != nil
      record["Boiling Point"] = match[0]
    end
  end

  url = PUG_REST + "https://pubchem.ncbi.nlm.nih.gov/sdq/sdqagent.cgi?infmt=json&outfmt=json&query=%7B%22download%22:%22*%22,%22collection%22:%22consolidatedcompoundtarget%22,%22order%22:[%22cid,asc%22],%22start%22:1,%22limit%22:10000000,%22downloadfilename%22:%22pubchem_cid_#{record["PubChemId"]}_consolidatedcompoundtarget%22,%22where%22:%7B%22ands%22:[%7B%22cid%22:%223007%22%7D]%7D%7D"
  inter_fetch = fetch(url, "application/json")
  if inter_fetch != nil
    inter_syms = JSON.parse(inter_fetch)
    if inter_syms != nil && !inter_syms.empty?
      #for inter in inter_syms[0]
      #  puts JSON.pretty_generate(inter)
      #end
    end
  end

  #if record["Toxicity Data"]
  #  record["Toxicity Data"].split("\n").each do |tox|
  #    puts tox
  #    if tox.start_with?("LD50:")
  #      ttox = tox.delete_prefix("LD50:").delete_suffix("(T14)").downcase.gsub("(", "").gsub(", ", " - ").gsub(")", "").strip
  #      record["LD50"] = [] if record["LD50"] == nil
  #      record["LD50"] << ttox
  #    end
  #  end
  #end
  url = 'https://pubchem.ncbi.nlm.nih.gov/sdq/sdqagent.cgi?infmt=json&outfmt=json&query=%7B"download":"*","collection":"consolidatedcompoundtarget","order":["cid,asc"],"start":1,"limit":10000000,"downloadfilename":"pubchem_cid_3007_consolidatedcompoundtarget","where":%7B"ands":[%7B"cid":"3007"%7D]%7D%7D'
  tox_syms = fetch(url, "application/json")&.then { |f| JSON.parse(f) rescue nil }
  if tox_syms != nil && tox_syms.length != 0
    puts "Toxicity Tests:"
    for test in 0...tox_syms.length
      next if tox_syms[test]["cid"] != record["PubChemId"].to_s
      next if tox_syms[test]["route"] == "unreported"
      next if tox_syms[test]["organism"] == nil

      organism = tox_syms[test]["organism"].capitalize().gsub("Infant", "Human - infant").gsub("Child", "Human - child").gsub("Man", "Human - male").gsub("Women", "Human - female")
      dosage = { route: tox_syms[test]["route"], amount: tox_syms[test]["dose"].gsub("ug/kg", "μg/kg").gsub("uL/kg", "μL/kg") }
      for type in ["LD50", "LC50", "LDLo", "TDLo"]
        if tox_syms[test]["testtype"] == type
          record[type] = [] if record[type] == nil
          entry = record[type].find { |h| h[:organism] == organism }
          if entry != nil
            entry[:dosages] << dosage
          else
              record[type] << { organism: organism, dosages: [ dosage ] }
          end
          break
        end
      end
      #elsif tox_syms[test]["testtype"] == "LDLo"
      #  record["LDLo"] = [] if record["LDLo"] == nil
      #  entry = record["LDLo"].find { |h| h[:organism] == organism }
      #  if entry != nil
      #    entry[:dosages] << dosage
      #  else
      #      record["LDLo"] << { organism: organism, dosages: [ dosage ] }
      #  end
      #elsif tox_syms[test]["testtype"] == "TDLo"
      #  record["TDLo"] = [] if record["TDLo"] == nil
      #  entry = record["TDLo"].find { |h| h[:organism] == organism }
      #  if entry != nil
      #    entry[:dosages] << dosage
      #  else
      #      record["TDLo"] << { organism: organism, dosages: [ dosage ] }
      #  end
      #end
      #puts "#{tox_syms[test]["testtype"]}: #{tox_syms[test]["dose"]}"
    end
    #for type in ["LD50", "LC50", "LDLo", "TDLo"]
    #  if record[type]
    #    record["Sum#{type}"] = ""
    #        record["Sum#{type}"] += "<strong>- #{dose[:route]}</strong>: #{dose[:amount]}<br>"
    #      end
    #    end
    #  end
    #end
    #if record["LDLo"]
    #  record["SumLDLo"] = ""
    #  for org in record["LDLo"] 
    #    record["SumLDLo"] += "<strong>#{org[:organism].capitalize}:</strong><br>"
    #    for dose in org[:dosages]
    #      record["SumLDLo"] += "<strong>- #{dose[:route]}</strong>: #{dose[:amount]}<br>"
    #    end
    #  end
    #end
    #if record["TDLo"]
    #  record["SumTDLo"] = ""
    #  for org in record["TDLo"] 
    #    record["SumTDLo"] += "<strong>#{org[:organism].capitalize}:</strong><br>"
    #    for dose in org[:dosages]
    #      record["SumTDLo"] += "<strong>- #{dose[:route]}</strong>: #{dose[:amount]}<br>"
    #    end
    #  end
    #end
  end
  record["Aliases"] = fetch_synonyms(record)

  if record["Refs"] == nil
    record["Refs"] = []
    record["RefCount"] = 1
    record["RefCur"] = ""
  end

  if record["Drug Classes"] != nil and record["Drug Classes"].include?("; ")
    record["Drug Classes"] = record["Drug Classes"].split("; ")
  end

  if record["ATC Code"] != nil
    record["ATC Code"] = record["ATC Code"].sort
  end

  now = Time.now
  record["Refs"] += [ "National Center for Biotechnology Information. PubChem Compound Summary for CID " + record["PubChemId"].to_s + ", " + record["Title"] +". Accessed #{now.strftime('%B')} #{now.day.to_s}, #{now.year.to_s}. <a href=https://pubchem.ncbi.nlm.nih.gov/compound/" + record["PubChemId"].to_s + ">https://pubchem.ncbi.nlm.nih.gov/compound/" + record["PubChemId"].to_s + "</a>" ]
  record["RefCount"] += 1

  return record
end
