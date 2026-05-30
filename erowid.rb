require 'nokogiri'

require_relative 'fetch'

require "json"
require "net/http"
require "nokogiri"
require "uri"

EROWID_BASE_URL = "https://www.erowid.org/experiences/"
SUBSTANCES_FILE = "/usr/src/chrp/erowid_substances.json"

HEADERS = {
  "User-Agent" => "Mozilla/5.0",
  "Host" => "www.erowid.org",
  "Accept" => "*/*"
}.freeze

def clean_text(el)
  return nil unless el

  text = el.text.strip
  text = text.gsub("\u00A0", " ")
  text = text.gsub(/\s+/, " ")
  text.empty? ? nil : text
end

def normalize_name(name)
  name.strip.downcase.gsub(/\s+/, " ")
end

def load_substances
  substances = JSON.parse(File.read(SUBSTANCES_FILE, encoding: "utf-8"))

  substances.each_with_object({}) do |item, acc|
    acc[normalize_name(item["name"])] = item
  end
end

def parse_dosechart(dose_table)
  return [] unless dose_table

  dose_table.css("tr").map do |tr|
    {
      "time" => clean_text(tr.at_css(".dosechart-time")),
      "amount" => clean_text(tr.at_css(".dosechart-amount")),
      "method" => clean_text(tr.at_css(".dosechart-method")),
      "substance" => clean_text(tr.at_css(".dosechart-substance")),
      "form" => clean_text(tr.at_css(".dosechart-form"))
    }
  end
end

def parse_intensity(details_row)
  return nil unless details_row

  text = details_row.text.strip.gsub(/\s+/, " ")
  match = text.match(/Intensity:\s*([A-Za-z]+)/)
  match ? match[1] : nil
end

def fetch_html(url)
  uri = URI(url)
  request = Net::HTTP::Get.new(uri)
  HEADERS.each { |key, value| request[key] = value }

  Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
    response = http.request(request)
    response.body
  end
end

def scrape_erowid_results(substance_id)
  url = "https://www.erowid.org/experiences/exp.cgi?Max=999999999&OldSort=RA_PDD&NewSort=&Start=0&ShowViews=1&S1=#{substance_id}&Cellar=0&ShowViews=1&SP=1"
  #doc = Nokogiri::HTML(fetch_html(url))
  doc = Nokogiri::HTML(fetch(url, "text/html"))
  results = []

  doc.css("tr.exp-list-row").each do |row|
    title_cell = row.at_css("td.exp-title a")
    rating_img = row.at_css("td.exp-rating img")
    author_cell = row.at_css("td.exp-author")
    substance_cell = row.at_css("td.exp-substance")
    pubdate_cell = row.at_css("td.exp-pubdate")

    href = title_cell ? title_cell["href"].to_s : ""
    match = href.match(/[?&]ID=(\d+)/)

    details_row = row.xpath("following-sibling::tr[1]").first
    dose_table = details_row&.at_css("table.dosechart")

    results << {
      "id" => match ? match[1].to_i : nil,
      "title" => clean_text(title_cell),
      "experience_link" => href.empty? ? nil : EROWID_BASE_URL + href,
      "rating" => rating_img ? rating_img["alt"] : nil,
      "author" => clean_text(author_cell),
      "substance" => clean_text(substance_cell),
      "pubdate" => clean_text(pubdate_cell),
      "intensity" => parse_intensity(details_row),
      "dosechart" => parse_dosechart(dose_table)
    }
  end

  return results
end

def scrape(aliases)
  substances_by_name = load_substances
  output = {}
  output["found"] = false
  output["reports"] = []

  aliases.each do |alias_name|
    key = normalize_name(alias_name)
    substance = substances_by_name[key]
    next unless substance

    reports = scrape_erowid_results(substance["id"])

    output["found"] = true
    #"id" => substance["id"],
    #  "total_reports" => reports.length,
    #  "name" => substance["name"],
    output["reports"] += reports
  end

  return output
end

def normalize_title(title)
  # Replace <U+0096> or similar Unicode representations with readable symbols
  # For example, replacing \u0096 (Unicode 'PRIVATE USE AREA') with a common character
  title.gsub(/[\u0096\u2013\u2014]/, '–').gsub(/[\u0092]/, '’')  # Replace with en dash (–) or use another symbol
end

def query_experiences(record)
  searches = [ record["Title"] ]
  if record["Abbreviation"] != nil and not record["Abbreviation"].empty?
    for abr in record["Abbreviation"]
      searches << abr
    end
  end
  for abr in record["Aliases"]
    searches << abr
  end
  searches.uniq!
  record["Erowid Experience Reports"] = [] if record["Erowid Experience Reports"] == nil or record["Erowid Experience Reports"].empty?

  data = scrape(searches)
  return record if data["found"] == false
  limit = 0
  for report in data["reports"].uniq { |hash| hash["id"] }
    limit += 1
    break if limit > 26
    puts JSON.pretty_generate(report)
    
    record["Erowid Experience Reports"] << {
      Title: report["title"],
      Author: report["author"],
      Id: report["id"]
    }
  end
  
  #url = "https://www.erowid.org/experiences/exp.cgi"
  #exp_text = fetch(encode_symbols(url), "text/html", cookies: { 'exp_max_results' => '999999999'})
  #document = Nokogiri::HTML(exp_text)
  #table = document.css('table.exp-list-table')

  #table.css('tr.exp-list-row').each do |row|
  #  title_link = row.css('td.exp-title a').attribute('href').to_s.strip
  #  id_match = title_link.match(/ID=(\d+)/)
  #  id = id_match ? id_match[1] : nil

  #  title = normalize_title(row.css('td.exp-title').text.strip)
  #  author = row.css('td.exp-author').text.strip
  #  substance = row.css('td.exp-substance').text.strip

  #  #next if substance.include?(searches)
  #  next if not searches.any? { |search| substance.downcase.include?(search.downcase) }
  #  next if id == nil

  #end
  return record

  #for s in searches
  #  #url = "https://api.erowid.io/search/drug?drug=#{record["Title"]}&fuzzy=false&limit=26"
  #  url = "https://methcathin.one/erw?drug=#{s}&fuzzy=false&limit=26"
  #  puts url
  #  json_text = HTTParty.get(encode_symbols(url))
  #  puts json_text
  #  json_text = HTTParty.get(encode_symbols(url))
  #  next if json_text.code != 200
  #  puts json_text
  #  json_syms = JSON.parse(json_text.body)
  #  next if json_syms.empty?
  #  puts JSON.pretty_generate(json_syms)
  #  
  #  for exp in json_syms
  #    next if not exp["drug"].include?(s.downcase)
  #  end
  #  return record
  #end
end
