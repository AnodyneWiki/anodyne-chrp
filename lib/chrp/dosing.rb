SHARVARA = "https://www.drug-do.se/sharvara?substance="

def query_dosing(prev_record)
  if prev_record == nil
    record = {}
  else
    record = prev_record
  end
  return record

  title = replace_symbols(record["Title"])
  url = SHARVARA + title
  json_content = fetch(url, "application/json")
  json_props = JSON.parse(json_content)

  record["Dosing Info"] = []
  for dose_range in json_props
    if dose_range["method"] == "IV"
      dose_range["method"] = "intravenous"
    end
    dose_range["method"] = dose_range["method"].capitalize()
    record["Dosing Info"] += [ { Method: dose_range["method"], Unit: dose_range["unit"], Tiers: dose_range["tiers"]} ]
  end

  return record
end
