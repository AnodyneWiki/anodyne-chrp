require 'httparty'

def query_experiences(record)
  #return record
  searches = [ record["Title"] ]
  for abr in record["Abbreviation"]
    searches << abr
  end
  for abr in record["Aliases"]
    searches << abr
  end
  searches.uniq!
  record["Erowid Experience Reports"] = [] if record["Erowid Experience Reports"] == nil or record["Erowid Experience Reports"].empty?
  for s in searches
    #url = "https://api.erowid.io/search/drug?drug=#{record["Title"]}&fuzzy=false&limit=26"
    url = "https://methcathin.one/erw?drug=#{s}&fuzzy=false&limit=26"
    puts url
    json_text = HTTParty.get(encode_symbols(url))
    puts json_text
    json_text = HTTParty.get(encode_symbols(url))
    next if json_text.code != 200
    puts json_text
    json_syms = JSON.parse(json_text.body)
    next if json_syms.empty?
    puts JSON.pretty_generate(json_syms)
    
    for exp in json_syms
      next if not exp["drug"].include?(s.downcase)
    end
    record["Erowid Experience Reports"] << {
      Title: exp["title"],
      Author: exp["author"],
      Id: exp["extra"]["exp_id"]
    }
    return record
  end
end
