CHEMBL_URL = "https://hmdb.ca/metabolites/"
CHEMBL_URL_END = ".xml"

def query_hmdb(prev_record)
  if prev_record == nil
    record = {}
  else
    record = prev_record
  end
  if record["CHEMBL"] == nil
    return record
  end

  url = CHEMBL_URL + record["CHEMBL"] + CHEMBL_URL_END

  return record
end
