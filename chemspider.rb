require 'json'

require_relative 'fetch'
require_relative 'text'

CHEMSPIDER_API = 'https://www.chemspider.com/api/search?value='

def query_chemspider(prev_record, compound)
  if prev_record == nil
    record = {}
  else
    record = prev_record
  end

  t_compound = replace_symbols(compound)
  url = CHEMSPIDER_API + t_compound
  json_props = JSON.parse(fetch(url, "application/json"))
  json_rec = json_props["Records"][0]
  if json_rec == nil
    return record
  end

  record["chemspiderId"] = json_rec["ChemSpiderId"]

  return record
end
