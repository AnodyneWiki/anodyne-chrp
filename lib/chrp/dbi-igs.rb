ROAS = [
  ["Buccal", "Buccal"],
  ["Insufflated", "Insufflated"],
  ["Intravenous", "Intravenous"],
  ["Subcutaneous", "Subcutaneous"],
  ["Intramuscular", "Intramuscular"],
  ["Sublingual", "Sublingual"],
  ["Oral", "Oral"],
  ["Rectal", "Intrarectal"],
  ["Smoked", "Vaporized"]
]
TIERS = [
  "Light", 
  "Common",
  "Strong",
  "Heavy",
  "Extreme"
]
LABELS = [
  "Statisticalhighdoses",
  "Riskthreshold",
  "Outliersdetected",
  "Cleandatamean",
  "Detectionbounds",
  "StdDev",
  "Median",
  "Mean",
  "Range",
  "Med"
]

require 'httparty'

def query_dbi_igs(record)
  #return record
  search_url = "https://dbi-igs.org/api/search.json"
  search_text = HTTParty.get(encode_symbols(search_url))
  return if search_text.code != 200
  search_syms = JSON.parse(search_text.body)

  aliases = [ record["Title"] ]

  aliases.concat(record["Aliases"]) if record["Aliases"] != nil and record["Aliases"].is_a?(Array)

  if record["Abbreviation"] != nil
    aliases.concat([ record["Abbreviation"] ]) if not record["Abbreviation"].is_a?(Array)
    aliases.concat(record["Abbreviation"]) if record["Abbreviation"].is_a?(Array)
  end
  
  if record["StereoisomerData"] != nil
    for ster in record["StereoisomerData"]
      aliases.concat([ ster["Title"] ]) if not record["Stereoisomers"].empty?
      aliases.concat(ster["Aliases"]) if not record["Stereoisomers"].empty?
      #aliases += ster["Title"] if ster["Title"] != nil
      #aliases += ster["Aliases"] if ster["Aliases"] != nil
    end
  end
  aliases.uniq!

  matches = []
  for aliase in aliases
    puts aliase
    found = search_syms.find { |s| s.casecmp?(aliase) }
    next if found == nil
    puts found
    matches << found
  end

  if matches.empty?
    puts "no matches found"
    return record
  end
  record["DBI-IGS"] = matches

  render_url = "https://dbi-igs.org/api/render/#{matches[0]}.json"
  render_text = HTTParty.get(encode_symbols(render_url))
  if render_text.code != 200
    puts "failed to fetch"
    return record
  end
  render_syms = JSON.parse(render_text.body)

  record["Dosing Info"] = [] if record["Dosing Info"] == nil

  for roa in ROAS
    next if render_syms[roa[0]] == nil
    route = { Method: roa[1], Tiers: {} }
    puts("route of administration: #{roa[1]}")
    render_out = render_syms[roa[0]]
    render_out.gsub!(/<span[^>]*>/, '')
    render_out.gsub!(/<\/span>/, '')
    render_out.gsub!(/&nbsp;/, '')
    render_out.gsub!(/<br \/>/, "\n")
    render_out.gsub!(/=/, "")
    render_out.each_line do |line|
      found = false
      for tier in TIERS
        if line.start_with?(tier)
          if line.start_with?("#{tier}doses")
            puts(line)
          else
            puts(line)
            line_ed = line.dup.delete_prefix(tier)
            puts(line_ed)
            dose = line_ed[/\(([^)]+)\)/, 1]
            if dose =~ /([≤<]?)(\d+(?:\.\d+)?)(?:-(\d+(?:\.\d+)?))?([a-zA-Z%]+)/
              comparator = $1       # optional ≤ or <
              lower = $2.to_f       # lower bound
              upper = $3 ? $3.to_f : nil  # upper bound if present
              if upper == nil
                upper = lower
              end
              unit = $4             # unit string
              route[:Tiers][tier] = { Lower: lower, Upper: upper, Unit: unit}
            end
            line_ed = line_ed.split(":", 2)[1]
            if line_ed =~ /(\d+)\s*entries\(([\d.]+)%\)/
              route[:Tiers][tier][:Entries] = $1.to_i
              route[:Tiers][tier][:Percentage] = $2.to_f
            end
            puts(line_ed)
            found = true
          end
        end
      end
      next if found
      for label in LABELS
        if line.start_with?(label)
          puts line
          break
        end
      end
    end
    same = ""
    for tier in route[:Tiers]
      puts JSON.pretty_generate(tier)
      break if same == nil
      same = tier[1][:Lower] if same == ""
      same = nil if same != "" and (tier[1][:Lower] != same or tier[1][:Upper] != same)
    end
    next if same != nil
    record["Dosing Info"] << route
    puts(JSON.pretty_generate(route))
    puts("\n")
  end

  return record
end
