require 'cgi'
require 'date'

require_relative 'text'
require_relative 'fetch'

WIKIPEDIA_URL = 'https://en.wikipedia.org/w/index.php?action=raw&title='

WHITELISTED_PATTERNS = [
  /^pronounce$/,
  /^tradename$/,
  /^pregnancy_[a-zA-Z0-9]{1,2}$/,
  /^pregnancy_[a-zA-Z0-9]{1,2}_comment$/,
  /^legal_[a-zA-Z0-9]{1,2}$/,
  /^legal_[a-zA-Z0-9]{1,2}_comment$/,
  /^legal_status$/,
  /^dependency_liability$/,
  /^addiction_liability$/,
  /^routes_of_administration$/,
  /^class$/,
  /^metabolism$/,
  /^metabolites$/,
  /^onset$/,
  /^elimination_half-life$/,
  /^duration_of_action$/,
  /^metabolites$/,
  /^excretion$/,
  /^CAS_number$/,
  /^ChEBI$/,
  /^PubChem$/,
  /^DrugBank$/,
  /^Drugs\.com$/,
  /^MedlinePlus$/,
  /^DailyMedID$/,
  /^ChemSpiderID$/,
  /^UNII$/,
  /^KEGG$/,
  /^ChEMBL$/,
  /^chirality$/,
  /^smiles$/,
  /^StdInChI$/,
  /^StdInChIKey$/,
  /^density$/,
  /^melting_point$/,
  /^boiling_point$/,
  /^solubility$/,
  /^sol_units$/
]

DRUGBOX_MAP = {
  "elimination_half-life" => "EliminationHalfLife",
  "duration_of_action" => "DurationOfAction",
}

COUNTRY_CODES = {
  "AU" => "Australia",
  "BR" => "Brazil",
  "CA" => "Canada",
  "EU" => "European Union",
  "UK" => "United Kingdom",
  "US" => "United States",
  "UN" => "United Nations",
  "NZ" => "New Zealand",
  "DE" => "Germany",
  "FR" => "France",
}

def key_whitelisted?(key)
  WHITELISTED_PATTERNS.any? { |pattern| pattern.match?(key) }
end

def extract_cite_templates(text)
end

def format_date(raw_date)
  return nil if raw_date == nil
  begin
    date = Date.parse(raw_date)
    date.strftime('%B %-d, %Y')
  rescue
    raw_date
  end
end

def parse_wikimedia_cite(template)
  return nil unless template.start_with?("{-{cite") && template.end_with?("}-}")
  content = template[7..-3]
  parts = content.split('|')
  type = parts.shift.strip
  data = { 'type' => type }

  parts.each do |part|
    key, value = part.split('=', 2).map(&:strip)
    data[key] = value if key && value
  end

  return data
end

def format_ama_citation(record, data)
  return nil unless data

  authors = data['vauthors'] || data['author']
  date = format_date(data['date'])
  title = data['title']
  website = data['website']
  url = data['url']
  publisher = data['publisher']
  journal = data['journal']
  volume = data['volume']
  issue = data['issue']
  pages = data['pages']

  puts "type: #{data['type']}"
  case data["type"].downcase
  when "web"
    citation = ""
    citation += "#{authors}. " if authors
    citation += "#{title}. " if title
    citation += "#{publisher}. " if publisher
    citation += "#{date}. " if date
      
    citation += "Accessed #{Date.today.strftime('%B %-d, %Y')}. <a href=#{url}>#{url}</a>" if url
    citation.strip
  when "journal"
    citation = ""
    citation += "#{authors}. " if authors
    citation += "#{title}. " if title
    citation += "#{journal}. " if journal
    citation += "#{date}; " if date
    citation += "#{volume}" if volume
    citation += "(#{issue})" if issue
    citation += ":#{pages}." if pages
    citation.strip
  when "report"
    citation = ""
    citation += "#{authors}. " if authors
    citation += "#{title}. " if title
    citation += "#{publisher}. " if publisher
    citation += "#{date}. " if date
    citation += "Accessed #{Date.today.strftime('%B %-d, %Y')}. <a href=#{url}>#{url}</a>" if url
    citation.strip
  when "book"
    citation = ""
    citation += "#{authors}. " if authors
    citation += "#{title}. " if title
    citation += "#{publisher}. " if publisher
    citation += "#{date}. " if date
    citation += "Accessed #{Date.today.strftime('%B %-d, %Y')}. <a href=#{url}>#{url}</a>" if url
    citation.strip
  when "encyclopedia"
    citation = ""
    citation += "#{authors}. " if authors
    citation += "#{title}. " if title
    citation += "#{publisher}. " if publisher
    citation += "#{date}. " if date
    citation += "Accessed #{Date.today.strftime('%B %-d, %Y')}. <a href=#{url}>#{url}</a>" if url
    citation.strip
  else
    puts "Unknown citation type: #{data["type"]}"
    nil
  end
end

def clean_wikitext(text)
  text.gsub!(/[ \t]+/, " ")
  text.gsub!(/\[\[.*?\|(.*?)\]\]/, '\1')
  text.gsub!(/\[\[(.*?)\]\]/, '\1')
  #text.gsub!(/\{\{cite[^}]*\}\}/m, '')
  #text.gsub!(/\{\{Cite[^}]*\}\}/m, '')
  text.gsub!(/\{\{\s*citation needed.*?\}\}/i, '')
  #text.gsub!(/<\/?ref[^>]*>/, '')
  #text.gsub!(/\{\{ubl\s*\|(.+?)\}\}/im) do
  #  items = $1.split(/\s*\|\s*/).map(&:strip)
  #  "\n" + items.map { |item| ",  #{item}" }.join("\n") + "\n"
  #  #"<ul>\n" + items.map { |item| "  <li>#{item}</li>" }.join("\n") + "\n</ul>"
  #end
  text.gsub!(/\{\{Val\|([^|{}]+?)\|u=([^|{}]+?)\}\}/i) do
    value = $1.strip
    unit = $2.strip
    unit += "s" unless value == "1" || unit.end_with?("s")
    "#{value} #{unit}"
  end

  text.gsub!(/\{\{Val\|(\d+)\|\-?\|(\d+)\|u=([^}]+?)\}\}/i) do
    start = $1.strip
    finish = $2.strip
    unit = $3.strip
    unit += "s" unless unit.end_with?("s") || start == finish
    "#{start}–#{finish} #{unit}"
  end
  return text.strip
end

def extract_infobox(wikitext)
  start_index = wikitext.index("{-{Drugbox")
  return nil unless start_index
  
  i = start_index + "{-{Drugbox".length
  brace_count = 2
  while i < wikitext.length && brace_count > 0
    if wikitext[i, 2] == '{-{'
      brace_count += 2
      i += 2
    elsif wikitext[i, 2] == '}-}'
      brace_count -= 2
      i += 2
    else
      i += 1
    end
  end

  return wikitext[start_index...i]
end


def parse_infobox(record, infobox)
  return {} unless infobox
  data = {}
  current_key = nil
  current_value_lines = []

  infobox.each_line do |line|
    if line =~ /^\|\s*([^=]+?)\s*=\s*(.*)$/
      if current_key
        data[current_key] = current_value_lines.join("\n").strip
      end

      current_key = $1.strip
      current_value_lines = [$2.strip]
    elsif current_key
      current_value_lines << line.strip
    end
  end

  if current_key
    data[current_key] = clean_wikitext(current_value_lines.join("\n"))
  end

  return data.select { |key, _| key_whitelisted?(key) }
end

def format_schedule(input, char)
  parts = input.split
  parts.shift if parts.first == char

  if parts.size == 1
    "Schedule #{parts[0]}"
  elsif parts.size == 2
    "Schedule #{parts[0]} and #{parts[1]}"
  else
    "Schedule #{parts[0..-2].join(', ')} and #{parts[-1]}"
  end
end

def extract_scheduling(record, data)
  return nil if data == nil
  scheduling = []

  data.each do |key, value|
    next unless key.start_with?("legal_") && !key.end_with?("_comment") && !key.end_with?("_status")
    comment = ""
    status = ""
    data.each do |skey, svalue|
      if skey.start_with?(key[0, 8])
        if skey.end_with?("_comment")
          comment = svalue
        elsif skey.end_with?("_status")
          status = svalue
        end
      end
    end

    gov_code = key.sub(/^legal_/, '')
    country = COUNTRY_CODES[gov_code] || gov_code
    act = nil
    post = "substance"

    next if value.strip.empty?
    value = value.delete_prefix("Psychotropic ").gsub("Rx-only", "prescription only").gsub("POM", "prescription only")
    value = value.strip

    if value.end_with?(".")
      post = nil
    end
    if value.start_with?("N I")
      value = format_schedule(value, 'N')
      act = "Single Convention on Narcotic Drugs 1961"
      post = "narcotic"
    elsif value.start_with?("P I")
      value = format_schedule(value, 'P')
      act = "Convention on Psychotropic Substances 1971"
      post = "drug"
    elsif value.start_with?("NpSG")
      value = "Neuer-Psychoaktiver-Stoff"
      act = "Neue-psychoaktive-Stoffe-Gesetz (NpSG)"
      post = nil
    end

    if value.length != 0
      if post != nil && !value.end_with?(post)
        value += " " + post
      end
      elm = {
        "gov" => country,
        "schedule" => value,
        "ref" => []
      }
      cvalue = value + comment + status
      cvalue.scan(/\{-\{cite.*?\}-\}/m) do |match|
        data = parse_wikimedia_cite(match)
        citation = format_ama_citation(record, data)
        if !citation || citation.size == 0
          return nil
        end
        record["Refs"] += [ citation ]
        rid = record["RefCount"].to_s
        record["RefCount"] += 1
        elm["ref"] += [ rid ]
        elm["schedule"].gsub!(match, "") #"<a href=#cite_note-#{rid}><sup>\[#{rid}\]<\/sup><\/a>")
      end

      if act != nil
        elm["act"] = act
      end
      elm["schedule"].gsub!(/\{\{.*?\}\}/m, "")
      scheduling << elm
    end
    if country == "United States"
      if value.start_with?("Schedule I") || value.end_with?("Schedule I")
        elm["schedule"] = "Schedule I"
        elm["act"] = "Controlled Substances Act (CSA)"
        post = "controlled substance."
      elsif value.start_with?("Schedule II") || value.end_with?("Schedule II")
        elm["schedule"] = "Schedule II"
        elm["act"] = "Controlled Substances Act (CSA)"
        post = "controlled substance."
      elsif value.start_with?("Schedule III") || value.end_with?("Schedule III")
        elm["schedule"] = "Schedule III"
        elm["act"] = "Controlled Substances Act (CSA)"
        post = "controlled substance."
      end
    end
  end

  return scheduling
end

def extract_section(wikitext, section)
  return wikitext[/^== #{section} ==\n(.*?)(?=^== )/m]
end

def query_wikipedia(record)
  #return record

  t_compound = record["Wikipedia"] if record["Wikipedia"] != nil
  t_compound = record["Title"] if t_compound == nil
  return record if t_compound == nil

  url = WIKIPEDIA_URL + encode_symbols(t_compound.gsub(" ", "_"))

  wikitext = fetch(url, "text/xwiki")
  puts "check" if wikitext == nil
  return record if wikitext == nil

  if wikitext =~ /^#REDIRECT\s*\[\[(.+?)\]\]/i
    target = $1.strip
    url = WIKIPEDIA_URL + encode_symbols(target.gsub(" ", "_"))
    wikitext = fetch(url, "text/xwiki")
    return record if wikitext == nil

    record["Wikipedia"] = target if record["Wikipedia"] == nil
  else
    record["Wikipedia"] = t_compound if record["Wikipedia"] == nil
  end

  puts "begin"
  puts extract_section(wikitext, "Pharmacology")
  puts "end"

  wikitext.gsub!("{{Infobox drug", "{{Drugbox")
  wikitext.gsub!("{{bulleted list", "{{ubl")
  wikitext.gsub!("{{Bulleted list", "{{ubl")
  wikitext.gsub!("{{unbulleted list", "{{ubl")
  wikitext.gsub!("{{Unbulleted list", "{{ubl")
  wikitext.gsub!("{{Cite", "{{cite")
  wikitext.gsub!("{{citation needed}}", "")
  wikitext.gsub!("{{Citation needed}}", "")
  wikitext.gsub!("{{nbsp}}", " ")
  wikitext.gsub!("{{nbsp}}", " ")
  wikitext.gsub!("{{cascite|correct|??}}", "")
  wikitext.gsub!("<\/ref>", "")
  wikitext.gsub!(/<ref[^>]*>/m, "")
  wikitext.gsub!(/<ref *\/>/m, "")
  wikitext.gsub!(/<!--.*?-->/m, "")
  wikitext.gsub!(/<br[^>]*\/?>/i, "")
  wikitext.gsub!(/\{\{nowrap\|(.*?)\}\}/i) { |match| $1.tr("–—", "-") }
  wikitext.gsub!(/\{\{abbr\|.*?\|(.*?)\}\}/i, '\1')
  wikitext.gsub!(/\{\{abbr\|([^|{}]+?)\}\}/i, '\1')
  wikitext.gsub!(/\{\{Abbrlink\|[^|{}]+?\|([^|{}]+?)\}\}/i, '\1')
  wikitext.gsub!(/\r\n?/, "\n")
  wikitext.gsub!("[[", "")
  wikitext.gsub!("]]", "")
  wikitext.gsub!(/\{\{citation needed\|.+?\}\}/m, "")
  wikitext.gsub!(/\{\{Citation needed\|.+?\}\}/m, "")
  wikitext.gsub!(/\{\{ubl.+?\}\}/m, "")
  wikitext.gsub!(/\{\{Better source needed.*?\}\}/i, '')
  wikitext.gsub!(/\{\{Additional citation needed.*?\}\}/i, '')
  wikitext.gsub!(/\{\{Request.quotation.*?\}\}/i, '')
  wikitext.gsub!(/\{\{underline\|(.+?)\}\}/, '<u>\1</u>')
  wikitext.gsub!(/\{\{Underline\|(.+?)\}\}/, '<u>\1</u>')
  wikitext.gsub!(/\{\{ndash\}\}/m, "-")
  wikitext.gsub!(/\{\{plainlist\|\s*(.*?)\s*\}\}/m) { #"<ul>" + 
    $1.scan(/^\* ?(.*)/).map { |m| #"<li>" + 
      m[0] #+ "</li>"
      }.join #+ "</ul>"
    }
  #wikitext.gsub!(/\{\{ubl\s*\|(.+?)\}\}/im) do
  #  $1.split(/\s*\|\s*/).map(&:strip).join(", ")
  #end
  wikitext.gsub!(/\{\{Val\|([^|{}]+?)\|u=([^|{}]+?)\}\}/i) do
    value = $1.strip
    unit = $2.strip
    unit += "s" unless value == "1" || unit.end_with?("s")
    "#{value} #{unit}"
  end

  wikitext.gsub!(/\{\{Val\|(\d+)\|\-?\|(\d+)\|u=([^}]+?)\}\}/i) do
    start = $1.strip
    finish = $2.strip
    unit = $3.strip
    unit += "s" unless unit.end_with?("s") || start == finish
    "#{start}–#{finish} #{unit}"
  end
  wikitext.gsub!("{{", "{-{")
  wikitext.gsub!("}}", "}-}")
  infobox = extract_infobox(wikitext)
  if infobox == nil
    return record
  end
  indata = parse_infobox(record, infobox)
  return record if indata == nil

  #puts JSON.pretty_generate(indata)

  sched = extract_scheduling(record, indata)
  record["Scheduling"] = sched if sched != nil

  indata.each do |ki, vi|
    next unless DRUGBOX_MAP[ki] != nil
    vd = vi.dup
    matches = vd.scan(/\{-\{cite.*?\}-\}/m)
    puts "#{matches.length}\n"
    matches.each do |match|
      rdata = parse_wikimedia_cite(match)
      if rdata == nil
        next
      end
      citation = format_ama_citation(record, rdata)
      if citation == nil
        next
      end
      record["Refs"] += [ citation ]
      rid = record["RefCount"]
      record["RefCount"] += 1
      vd.gsub!(match, "<a href='#cite_note-#{rid}'><sup>\[#{rid}\]<\/sup><\/a>")
      record[DRUGBOX_MAP[ki]] = vd
    end
    record[DRUGBOX_MAP[ki]] = vd
  end
  if record["EliminationHalfLife"]
    record["EliminationHalfLife"].gsub!("hrs", "hours")
    record["EliminationHalfLife"].gsub!(" to ", " - ")
    record["EliminationHalfLife"].gsub!(/(\d+(?:\.\d+)?)[\-\u2013\u2014](\d+(?:\.\d+)?)/, '\1 – \2')
    record["EliminationHalfLife"].gsub!("Up - ", "")
    record["EliminationHalfLife"].gsub!("{{cascite|correct|??}}", "")
  end
  if record["DurationOfAction"]
    record["DurationOfAction"].gsub!("hrs", "hours")
    record["DurationOfAction"].gsub!(" to ", " - ")
    record["DurationOfAction"].gsub!(/(\d+(?:\.\d+)?)[\-\u2013\u2014](\d+(?:\.\d+)?)/, '\1 – \2')
    record["DurationOfAction"].gsub!("Up - ", "")
  end

  return record
end
