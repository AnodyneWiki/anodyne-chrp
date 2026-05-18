require "json"
require "net/http"
require "uri"
require "nokogiri"

BASE_URL = "https://isomerdesign.com/pihkal/explore"

def fetch_html(substance_id)
  url = URI("#{BASE_URL}/#{substance_id}")
  response = Net::HTTP.get_response(url)
  raise "HTTP #{response.code}: #{response.message}" unless response.is_a?(Net::HTTPSuccess)
  response.body
end

def parse_jsonld(doc)
  script = doc.at_css('script[type="application/ld+json"]')
  return {} unless script

  raw = script.content
  begin
    data = JSON.parse(raw)
  rescue JSON::ParserError
    return {}
  end

  rep = data.dig("hasRepresentation", "value")

  {
    "id"        => data["identifier"],
    "name"      => data["name"],
    "iupac_name"=> data["iupacName"],
    "formula"   => data["molecularFormula"],
    "inchi"     => data["inChI"],
    "inchi_key" => data["inChIKey"],
    "smiles"    => data["smiles"],
    "url"       => data["url"]
  }
end

def parse_names(doc)
  common_names = []
  iupac_names = []

  doc.css("ul.name-list").each do |ul|
    parent_row = ul.ancestors("div.row").first
    label = nil
    if parent_row
      lbl = parent_row.at_css("label.sLabel")
      label = lbl.text.strip.rstrip(":") if lbl
    end

    ul.css("li").each do |li|
      name_div = li.at_css("div.clippable")
      next unless name_div
      text = name_div.text.strip
      if label == "IUPAC name"
        iupac_names << text
      else
        common_names << text
      end
    end
  end

  [common_names.empty? ? nil : common_names,
   iupac_names.empty? ? nil : iupac_names]
end

def parse_properties(doc)
  props = {}

  doc.css("div.card-body div.row, .tab-content div.row").each do |row|
    children = row.children.to_a
    i = 0
    while i < children.length
      child = children[i]
      if child.element? && child.name == "div"
        label = child.at_css("label.sLabel")
        if label
          key = label.text.strip.rstrip(":")
          value = nil
          i += 1
          while i < children.length
            nc = children[i]
            if nc.element? && nc.name == "div"
              next_label = nc.at_css("label.sLabel")
              break if next_label
              clip = nc.at_css("span.clippable")
              if clip
                value = clip.text.strip
                break
              end
            end
            i += 1
          end
          unless value.nil?
            case key
            when "ID"                  then props["id"] = value
            when "Formula"             then props["formula"] = value
            when "Molecular weight"    then props["molecular_weight"] = value
            end
          end
        end
      end
      i += 1
    end
  end

  props
end

def parse_tags(doc)
  doc.css("div.col-8 > div.row, div.col-8 div.row, div.col-8 > div").each do |row|
    label = row.at_css("label.sLabel")
    next unless label && label.text.include?("Tags")

    parts = []
    row.children.each do |child|
      next if child == label
      if child.element?
        if child.name == "span" && (child["class"] || "").include?("middot")
          next
        end
        text = child.text.strip
        parts << text if text.length > 0
      else
        text = child.text.strip
        parts << text if text.length > 0 && text != "\u00b7"
      end
    end

    if parts.empty?
      raw = row.text.strip
      raw = raw.sub(label.text.strip, "").strip
      parts = [raw] unless raw.empty?
    end

    return parts.empty? ? nil : parts
  end

  nil
end

def parse_xrefs(doc)
  xref_pane = doc.at_css("div#xrefs")
  return nil unless xref_pane

  xrefs_pihkal = []
  xrefs_pea    = []

  xref_pane.css("table").each do |table|
    caption = table.at_css("caption")
    next unless caption
    caption_text = caption.text.strip

    rows = []
    headers = []
    thead = table.at_css("thead")
    if thead
      headers = thead.css("th").map { |th| th.text.strip.downcase }
    end

    tbody = table.at_css("tbody")
    (tbody ? tbody.css("tr") : []).each do |tr|
      cells = tr.css("td")
      row_data = {}
      cells.each_with_index do |td, idx|
        key = idx < headers.length ? headers[idx] : "col_#{idx}"
        a = td.at_css("a")
        if a
          row_data[key] = {
            "text" => a.text.strip,
            "href" => a["href"].to_s
          }
        else
          row_data[key] = td.text.strip
        end
      end
      rows << row_data
    end

    lower = caption_text.downcase
    if lower.include?("pihkal")
      xrefs_pihkal = rows
    elsif lower.include?("phenethylamine") || lower.include?("pea")
      xrefs_pea = rows
    end
  end

  result = {}
  result["pihkal"] = xrefs_pihkal unless xrefs_pihkal.empty?
  result["pea"]    = xrefs_pea    unless xrefs_pea.empty?
  result.empty? ? nil : result
end

def parse_links(doc)
  links_pane = doc.at_css("div#links")
  return nil unless links_pane

  links = []
  tbody = links_pane.at_css("tbody")
  return nil unless tbody

  tbody.css("tr").each do |tr|
    tds = tr.css("td")
    next if tds.length < 2

    source    = tds[0].text.strip
    see_cell  = tds[1]
    a_tags    = see_cell.css("a[href]")

    if a_tags.any?
      a_tags.each do |a|
        links << {
          "source"  => source,
          "title"   => a.text.strip,
          "url"     => a["href"],
          "context" => see_cell.text.strip
        }
      end
    else
      links << {
        "source"  => source,
        "title"   => see_cell.text.strip,
        "url"     => nil,
        "context" => see_cell.text.strip
      }
    end
  end

  links.empty? ? nil : links
end

def parse_isomers(doc)
  isomers_pane = doc.at_css("div#isomers")
  return nil unless isomers_pane

  isomers = []

  isomers_pane.css("div.card").each do |card|
    name_btn = card.at_css("button")
    name = name_btn ? name_btn.text.strip : nil

    substance_id = nil
    card.css("a[href]").each do |a|
      m = %r{/explore/(\d+)}.match(a["href"])
      if m
        substance_id = m[1].to_i
        break
      end
    end

    tooltip_div = card.at_css('div[data-toggle="tooltip"]')
    tooltip_title = tooltip_div ? tooltip_div["title"] : nil

    isomers << {
      "id"      => substance_id,
      "name"    => name,
      "tooltip" => tooltip_title
    }
  end

  isomers.empty? ? nil : isomers
end

def parse_navigation(doc, substance_id)
  nav = {}
  sid_int = substance_id.to_i

  nav_header = doc.at_css("#nav-header")
  if nav_header
    nav_header.css("a[href]").each do |a|
      m = %r{/explore/(\d+)}.match(a["href"])
      next unless m
      link_id = m[1].to_i
      if link_id < sid_int
        nav["prev_id"] = link_id
      elsif link_id > sid_int
        nav["next_id"] = link_id
      end
    end
  end

  prev_a = doc.at_css("a#link-prev")
  if prev_a
    classes = prev_a["class"] || ""
    unless classes.include?("disabled")
      m = %r{/explore/(\d+)}.match(prev_a["href"].to_s)
      nav["prev"] = m[1].to_i if m
    end
  end

  next_a = doc.at_css("a#link-next")
  if next_a
    classes = next_a["class"] || ""
    unless classes.include?("disabled")
      m = %r{/explore/(\d+)}.match(next_a["href"].to_s)
      nav["next"] = m[1].to_i if m
    end
  end

  nav.empty? ? nil : nav
end

def get_substance_id(substance)
  uri = URI("https://isomerdesign.com/pihkal/lookup/json")
  uri.query = URI.encode_www_form("q" => substance)
  resp = Net::HTTP.get_response(uri)
  return false unless resp.body.include?("<b>")

  JSON.parse(resp.body)[0]["substance_id"]
end

def scrape(substance_id)
  html_text = fetch_html(substance_id)
  doc = Nokogiri::HTML(html_text, nil, "utf-8")

  ld            = parse_jsonld(doc)
  props         = parse_properties(doc)
  common_names, iupac_names = parse_names(doc)
  tags          = parse_tags(doc)

  {
    "id"               => props["id"] || ld["id"],
    "name"             => ld["name"],
    "names"            => common_names,
    "iupac_name"       => ld["iupac_name"] || (iupac_names ? iupac_names[0] : nil),
    "formula"          => props["formula"] || ld["formula"],
    "molecular_weight" => props["molecular_weight"],
    "inchi"            => ld["inchi"],
    "inchi_key"        => ld["inchi_key"],
    "smiles"           => ld["smiles"],
    "url"              => ld["url"],
    "tags"             => tags,
    "xrefs"            => parse_xrefs(doc),
    "links"            => parse_links(doc),
    "isomers"          => parse_isomers(doc),
    "navigation"       => parse_navigation(doc, substance_id)
  }
end

def main(substance)
  substance_id = get_substance_id(substance)
  return false unless substance_id

  data = scrape(substance_id)
  JSON.pretty_generate(data)
end

if __FILE__ == $PROGRAM_NAME
  if ARGV.length < 1
    STDERR.puts "Usage: ruby #{$PROGRAM_NAME} <substance_name>"
    exit 1
  end
  result = main(ARGV[0])
  puts result
end