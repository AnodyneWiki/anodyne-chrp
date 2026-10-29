require 'net/http'
require 'uri'
require 'csv'
require 'json'
require 'nokogiri'

TP_URL = "http://old.swisstargetprediction.ch/"
PREDICT = "predict.php"
RESULT = "result.php"
CSV_ST = "results/"
CSV_END = "/TargetPredictionReport.csv"
SPECIES = "Homo_sapiens"

def query_swtp(prev_record)
  if prev_record == nil
    record = {}
  else
    record = prev_record
  end
  if record["SMILES"] == nil
    return record
  end

  url = TP_URL + PREDICT
  uri = URI.parse(url)
  request = Net::HTTP::Post.new(uri)
  request.set_form_data(
    "organism" => SPECIES,
    "smiles" => record["SMILES"]
  )
  response = Net::HTTP.start(uri.hostname, uri.port) do |http|
    http.request(request)
  end

  body = response.body

  job_id = nil
  if !(match = body.match(/location\.replace\((.*?)\)/))
    puts "No location.replace() found."
    return record
  else
    location_arg = match[1].strip.gsub(/^['"]|['"]$/, '')  # remove wrapping quotes
    puts "Redirect target: #{location_arg}"
    if !(job_match = location_arg.match(/job=(\d+)/))
      puts "No job ID found in location.replace."
      return record
    else
      job_id = job_match[1]
      puts "Extracted job ID: #{job_id}"
    end
  end

  if job_id == nil
    return record
  end

  sleep 30
  url = TP_URL + RESULT + "?job=#{job_id}&organism=#{SPECIES}"
  result_fetch = fetch(url, "application/html")#, TP_URL + RESULT + "?smiles=#{record["SMILES"]}&organism=#{SPECIES}")
  #result_doc = Nokogiri::HTML(result_fetch)

  #csv_string = nil
  #result_doc.css('table').each_with_index do |table, index|
  #  table.css('col, colgroup').remove
  #  puts "Table ##{index + 1}:"
  #  csv_data = []
  #  table.css('tr').each do |row|
  #    cells = row.css('td').map do |cell|
  #      text = cell.text.gsub(/\s+/, ' ').strip  # Normalize all whitespace to single space
  #      "\"#{text.gsub('"', '""')}\""            # Escape internal quotes by doubling them
  #    end
  #    csv_data << cells
  #  end
  #  csv_string = csv_data.map { |row| row.join(',') }.join("\n")
  #  #puts "-" * 40
  #end

  url = TP_URL + CSV_ST + job_id.to_s + CSV_END
  csv_fetch = fetch(url, "text/csv; charset=utf-8")#, TP_URL + CSV_ST + record["SMILES"] + CSV_END)
  csv = CSV.parse('"Target","Common name","Uniprot ID","ChEMBL ID","Probability","Number of sim. cmpds (3D / 2D)","Target Class"' + csv_string, headers: true)
  data = csv.map(&:to_h)
  puts JSON.pretty_generate(data)
  record["SwissTargetPredictions"] = data
  return record
end
