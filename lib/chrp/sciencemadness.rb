SCIENCEMADNESS_URL = 'https://www.sciencemadness.org/smwiki/index.php?action=raw&title='

def query_sciencemadness(prev_record)
  if prev_record == nil
    record = {}
  else
    record = prev_record
  end
  t_compound = record["Title"]
  if record["ScienceMadness"] != nil
    t_compound = record["ScienceMadness"]
  end
  if t_compound == nil
    return record
  end

  url = SCIENCEMADNESS_URL + encode_symbols(t_compound.gsub(" ", "_"))

  wikitext = fetch(url, "text/xwiki")
  if wikitext == nil
    return record
  end

  if wikitext =~ /^#REDIRECT\s*\[\[(.+?)\]\]/i
    target = $1.strip
    url = WIKIPEDIA_URL + encode_symbols(target.gsub(" ", "_"))
    wikitext = fetch(url, "text/xwiki")
    if record["ScienceMadness"] == nil
      record["ScienceMadness"] = target
    end
  else
    if record["ScienceMadness"] == nil
      record["ScienceMadness"] = t_compound
    end
  end
  return record
end
