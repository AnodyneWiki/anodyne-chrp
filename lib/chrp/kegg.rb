require 'httparty'
require 'json'
require 'optparse'

require_relative 'fetch'
require_relative 'text'

def fetch_ddi_kegg_interactions(id)
  interactions = []
  url = "https://rest.kegg.jp/ddi/#{id}"; puts url
  #ddi_req = HTTParty.get(url)
  ddi_req = fetch(encode_symbols(url), "application/json")

  if ddi_req == nil
    puts "failed to fetch interactions"
    return interactions
  end

  ddi_req.each_line do | line |
    parts = line.split(":")
    next if parts == nil
    fid = parts[1][0, 6]
    sid = parts[2][0, 6]
    inter = parts[2..].join
    inter = inter[6..]
    next if inter.include?("unclassified")

    toks = inter.split()
    pre = toks[0]
    targets = []
    actions = []
    for tok in toks[1..]
      puts tok
      next if tok.include?("Enzyme:") or tok.include?("Target:") or tok.include?("/")
      if tok.include?("CYP") #or tok.include?("SLC") or tok.include?("ADR")
        targets.push(tok) if tok.length != 3
      elsif tok.include?("inhibition")
        actions.push("inhibition")
      elsif tok.include?("induction")
        actions.push("induction")
      end
    end
    next if targets.empty?
    next if actions.empty?
    target = targets.join
    action = actions[0]
    for target in targets
      next if interactions.any? { |h| h[:Target] == target and h[:Action] == action }
      interaction = Hash.new if interaction == nil
      interaction[:Target] = target
      interaction[:Action] = action
      interactions.push(interaction)
    end
  end

  return interactions
end

def query_kegg(record)
  #return record
  return record if record["Title"] == nil
  aliases = [ record["Title"] ]
  aliases += record["Aliases"][0..4] if record["Aliases"] != nil and not record["Aliases"].empty?

  caliases = [ record["Title"] ]
  caliases += record["Aliases"] if record["Aliases"] != nil and not record["Aliases"].empty?

  if record["SaltData"] != nil
    for salt in record["SaltData"]
      caliases += [ salt["Title"] ] if salt["Title"] != nil

      if record["Stereoisomers"] != nil
        for ster in record["Stereoisomers"]
          caliases += [ "#{ster} #{salt['Name']}" ]
          caliases += [ "#{ster} #{salt['RName']}" ]
        end
      end
    end
  end

  puts caliases

  for al in aliases 
    next if al == nil or al == ""

    url = "https://rest.kegg.jp/find/drug/#{encode_symbols al}"; puts url
    #kegg_text = HTTParty.get(url)
    kegg_req = fetch(url, "application/json")

    next if kegg_req == nil

    kegg_req.each_line do | line |
      next if line == nil or line.length <= 9
      line[9] = ':'
      parts = line.split(":")
      next if parts == nil
      next if parts.empty?
      next if parts.length > 3
      #next if parts.length < 2
      next if parts.length < 3
      synonyms = parts[2].split("; ")
      synonyms.map! { _1.strip.sub(/\s*\(.*\)\z/, '') }
      next if synonyms.empty?
      next if not (synonyms.map(&:downcase) & caliases.map(&:downcase)).any?
      id = parts[1]

      puts "#{id} found"
      entry = {
        Id: id,
        Synonyms: synonyms,
        Interactions: []
      }
      record["KEGG Entries"] = [] if record["KEGG Entries"] == nil
      entry[:Interactions] = fetch_ddi_kegg_interactions(id)
      puts JSON.pretty_generate(entry)
      record["KEGG Entries"].push(entry)
    end
    break if record["KEGG Entries"] == nil or record["KEGG Entries"].empty?
  end
  return record
end
