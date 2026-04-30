require 'json'
require 'date'

require_relative 'config'
require_relative 'fetch'
require_relative 'forms'

UNII_API = "https://gsrs.ncats.nih.gov/api/v1/substances("
#UNII_API = "https://gsrs.ncats.nih.gov/api/v1/substances/"
UNII_API_END = ")?view=internal"
#UNII_API_END = ""

UNII_SEARCH = "https://gsrs.ncats.nih.gov/api/v1/substances/search?q=root_names_name%3A%22%5E"
UNII_SEARCH_END = "%22&facet=Deprecated%2FNot%20Deprecated&top=10&skip=0&fdim=10"

def query_unii(root, prev_record, moieties, aminemoiety, acidmoiety)
  puts "Querying UNII"
  record = nil
  if prev_record == nil
    record = {}
  else
    record = prev_record
  end
  return record if record["UNII"] == nil
  salt = {}

  url = UNII_API + record["UNII"] + UNII_API_END
  json_fetch = fetch(url, "application/json")
  return record if json_fetch == nil
  json_props = JSON.parse(json_fetch)
  return record if json_props == nil
  json_struct = json_props["structure"] # molfile, stereochemistry, opticalActivity

  record["Records"] = {} if record["Records"] == nil
  record["Records"]["UNII"] = {} if record["Records"]["UNII"] == nil
  record["Records"]["UNII"]["Impurities"] = [] if record["Records"]["UNII"]["Impurities"] == nil

  #saltstruct = {}
  if moieties
    record["Chirality"] = json_struct['stereochemistry'].downcase if json_struct['stereochemistry'] != nil
    record["Opticalactivity"] = json_struct['opticalActivity'] if json_struct["opticalActivity"] != nil && json_struct["opticalActivity"] != "NONE"

    for rel in json_props["relationships"]
      puts "UNII Relationship: #{rel["type"]} #{rel["relatedSubstance"]["name"]}"
      if rel["type"] == "SALT/SOLVATE->PARENT"
        for key in SALTS.keys
          salt["Name"] = rel["relatedSubstance"]["name"].downcase.delete_prefix(json_props["_name"].downcase).strip
          salt["Name"] = salt["Name"].delete_prefix(record["Title"].downcase).strip
          salt["Name"] = salt["Name"].delete_prefix(record["Abr"]).strip if record["Abr"]
          salt["Name"] = salt["Name"].delete_suffix(", dl-").strip
          salt["Name"] = salt["Name"].delete_suffix(", l-").strip
          salt["Name"] = salt["Name"].delete_suffix(", d-").strip
          salt["RName"] = salt["Name"]
          #next if root["Salts"].include?(salt["Name"])
          puts "Salt name: #{salt["Name"]}"
          #next if not salt["Name"].include?(key.downcase)
          next if not salt["Name"] == key.downcase
          #salt["Name"] = key
          salt["UNII"] = rel["relatedSubstance"]["linkingID"]

          if moieties && json_struct != nil
            tmp_record = {}
            tmp_record["UNII"] = rel["relatedSubstance"]["linkingID"]
            hmoiety = json_struct["hash"].split("_")[0]
            tmp_record = query_unii(root, tmp_record, false, hmoiety, SALTS[key][:unii])
            salt["Formula"] = SALTS[key][:formula]
            salt["AmineCount"] = SALTS[key][:amine_count]
            salt["AcidCount"] = SALTS[key][:acid_count]
            salt["AmineCount"] = tmp_record["AmineMoietyCount"] if tmp_record["AmineMoietyCount"] != nil
            salt["AcidCount"] = tmp_record["AcidMoietyCount"] if tmp_record["AcidMoietyCount"] != nil
            if 1 < salt["AcidCount"]
              salt["Name"] = "#{count_prefix(salt['AcidCount'])}#{salt['Name'].downcase}"
            elsif 1 == salt["AcidCount"] and 2 == salt["AmineCount"]
              salt["Name"] = "hemi#{salt['Name'].downcase}"
            end
            salt["Amine"] = "#{root['Title']}"
            salt["Amine"] = "#{count_prefix(salt['AmineCount']).capitalize}#{salt['Amine'].downcase}" if 1 < salt["AmineCount"] and ( salt["AmineCount"] != 2 || not(salt['Name'].start_with?("hemi")) )
            if ["sodium", "potassium" ].include?(salt["Name"])
              salt["Title"] = "#{salt['Name'].capitalize()} #{salt['Amine'].downcase}" if key == "sodium"
            else
              salt["Title"] = "#{salt['Amine']} #{salt['Name']}"
            end
            next if root["Salts"].include?(salt["Name"])
            root["SaltData"] << salt.dup
            root["Salts"] << salt["Name"].dup
          end
        end
      #elsif rel["type"] == "PRODRUG->METABOLITE ACTIVE"
      #  if record["Esters"] == nil
      #    record["Esters"] = []
      #  end
      #  record["Esters"] += [ rel["relatedSubstance"]["name"].downcase] #.sub(/^#{Regexp.escape("#{record["Title"].downcase} ")}/, '') ]
      elsif rel["type"] == "IMPURITY->PARENT"
        record["Records"]["UNII"]["Impurities"] += [ rel["relatedSubstance"]["name"].downcase ]
        record["Records"]["UNII"]["Impurities"] = record["Records"]["UNII"]["Impurities"].uniq
      end
    end

    #if record["Esters"] != nil
    #  record["Esters"] = record["Esters"].uniq
    #  record["Esters"] = record["Esters"].flat_map { |str| ESTERS.keys.select { |filter| str.include?(filter) } }.uniq
    #  if record["Esters"].length == 0
    #    record["Esters"] = nil
    #  end
    #end

    for code in json_props["codes"]
      if code["codeSystem"] == "LIVERTOX" || code["codeSystem"] == "WIKIPEDIA"
        if code["comments"] != nil
          if record["Record Description"] == nil
            record["Record Description"] = []
          end
          record["Record Description"] += [ code["comments"] ]
        end
      end
    end
  elsif aminemoiety != nil || acidmoiety != nil
    log = "Fetching Form (Salt): #{record["Title"]}"
    mlog = ""
    if json_props["moieties"]
      for moi in json_props["moieties"]
        if moi["hash"].split("_")[0] == aminemoiety && moi["count"] != nil
          record["AmineMoietyCount"] = moi["count"]
          log += "Amine: [Moiety Hash: #{moi["hash"].split("_")[0]}, Moiety Count: #{moi["count"]}] "
        elsif moi["hash"].split("_")[0] == acidmoiety && moi["count"] != nil
          record["AcidMoietyCount"] = moi["count"]
          log += "Acid: [Moiety Hash: #{moi["hash"].split("_")[0]}, Moiety Count: #{moi["count"]}] "
        else
          if mlog == ""
            mlog += " ( "
          end
          mlog += "Unknown: [Moiety Hash: #{moi["hash"].split("_")[0]}, Moiety Count: #{moi["count"]}] "
        end
      end
    end
    if mlog != ""
      mlog += ")"
    end
    puts mlog
  end

  if record["Refs"] == nil
    record["Refs"] = []
    record["RefCount"] = 1
    record["RefCur"] = ""
  end

  if record["RefCount"] == nil
    record["RefCount"] = 1
  end

  now = Time.now
  record['Refs'] += [ "U.S. Food and Drug Administration; National Center for Advancing Translational Sciences. #{record['Title']}. UNII: #{record['UNII']}. Global Substance Registration System. Accessed #{now.strftime('%B')} #{now.day.to_s}, #{now.year.to_s}. <a href=https://gsrs.ncats.nih.gov/ginas/app/beta/substances/#{record['UNII']}>https://gsrs.ncats.nih.gov/ginas/app/beta/substances/#{record['UNII']}</a>" ]
  record["RefCount"] += 1

  return record
end
