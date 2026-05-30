require 'net/http'
require 'uri'
require 'json'
require 'time'
require 'openssl'

TIMEOUT = 45
CHUNK_ID = "7085"
PROTESTKIT_URL = "https://protestkit.us/drugspro/"
ASSET_MANIFEST_URL = PROTESTKIT_URL + "asset-manifest.json"
TARGET_ROUTE_URL = PROTESTKIT_URL + "reagents/analyze"
USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36"

def now_iso
  Time.now.utc.iso8601
end

COLOR_TO_HEX = {
  "white"   => "#ffffff",
  "white1"  => "#ffffff",
  "black1"  => "#bfbfbf",
  "black2"  => "#666666",
  "black3"  => "#111111",
  "blue1"   => "#41a7f8",
  "blue2"   => "rgba(0,103,206,1)",
  "blue3"   => "#020f69",
  "green1"  => "#7aefa6",
  "green2"  => "#3f8a1f",
  "green3"  => "#204a1c",
  "yellow1" => "#ffffcc",
  "yellow2" => "#f0d41d",
  "yellow3" => "#deb22e",
  "orange1" => "#fde9d9",
  "orange2" => "#fd7322",
  "orange3" => "#c04d01",
  "brown1"  => "#8e563a",
  "brown2"  => "#51240b",
  "brown3"  => "#320a0b",
  "red1"    => "#ff6666",
  "red2"    => "#ff0000",
  "red3"    => "#8c113e",
  "pink1"   => "#d59aca",
  "pink2"   => "#ff6fcf",
  "pink3"   => "#830c93",
  "purple1" => "#8064a2",
  "purple2" => "#50268d",
  "purple3" => "#270d45",
}.freeze

def color_to_hex(name)
  COLOR_TO_HEX[name.to_s.downcase]
end

def fetch_text(url)
  uri = URI.parse(url)
  req = Net::HTTP::Get.new(uri)
  req['User-Agent'] = USER_AGENT
  req['Accept'] = '*/*'

  start_time = Time.now

  begin
    res = Net::HTTP.start(uri.host, uri.port,
                          use_ssl: uri.scheme == 'https',
                          read_timeout: TIMEOUT,
                          open_timeout: TIMEOUT) do |http|
      http.request(req)
    end

    charset = res.type_params['charset'] || 'utf-8'
    text = res.body.encode('utf-8', charset, invalid: :replace, undef: :replace)

    {
      ok: res.is_a?(Net::HTTPSuccess),
      status: res.code.to_i,
      url: url,
      headers: res.each_header.to_h,
      text: text,
      elapsed_ms: ((Time.now - start_time) * 1000).round
    }
  rescue Net::HTTPExceptions => e
    {
      ok: false,
      status: e.response.code.to_i,
      url: url,
      headers: e.response.each_header.to_h,
      text: e.response.body || '',
      elapsed_ms: ((Time.now - start_time) * 1000).round
    }
  rescue StandardError => e
    {
      ok: false,
      status: nil,
      url: url,
      headers: {},
      text: e.message,
      elapsed_ms: ((Time.now - start_time) * 1000).round
    }
  end
end

def discover_chunk_url
  manifest_res = fetch_text(ASSET_MANIFEST_URL)
  if manifest_res[:ok]
    begin
      manifest = JSON.parse(manifest_res[:text])
      manifest_text = manifest.to_json
      if match = manifest_text.match(%r{/static/js/#{CHUNK_ID}\.[a-f0-9]+\.chunk\.js})
        return PROTESTKIT_URL.chomp('/') + match[0]
      end
    rescue
      # ignore
    end
  end

  route_res = fetch_text(TARGET_ROUTE_URL)
  if route_res[:ok]
    html = route_res[:text]
    script_refs = html.scan(/<script[^>]+src="([^"]+)"/i).flatten

    script_refs.each do |ref|
      if ref.match(%r{/static/js/#{CHUNK_ID}\.[a-f0-9]+\.chunk\.js})
        return ref.start_with?('http') ? ref : PROTESTKIT_URL.chomp('/') + ref
      end
    end

    main_ref = script_refs.find { |ref| ref.include?('/static/js/main.') }
    if main_ref
      main_url = main_ref.start_with?('http') ? main_ref : PROTESTKIT_URL.chomp('/') + main_ref
      main_res = fetch_text(main_url)
      if main_res[:ok] && (m = main_res[:text].match(/#{CHUNK_ID}\.[a-f0-9]+\.chunk\.js/))
        return PROTESTKIT_URL + "static/js/" + m[0]
      end
    end
  end

  raise "Could not discover current #{CHUNK_ID} analyzer chunk URL dynamically"
end

def extract_embedded_json(chunk_text)
  match = chunk_text.match(/const\s+r=JSON\.parse\('((?:\\.|[^'])*)'\)/)
  raise "Embedded analyzer JSON payload not found in chunk" unless match

  payload = match[1].gsub(/\\u([\da-fA-F]{4})/) { [$1.hex].pack('U') }
  JSON.parse(payload)
end

def build_output(master, chunk_url)
  colors = master["Tj"]
  reagents = master["aZ"]
  substances = master["sE"]
  reaction_matrix = master["Xv"]

  reagent_by_id = reagents.transform_keys(&:to_i)
  color_by_id = colors.transform_keys(&:to_i)

  output = {
    generated_at: now_iso,
    source: {
      chunk_url: chunk_url,
      chunk_id: CHUNK_ID
    },
    counts: {
      colors: colors.size,
      reagents: reagents.size,
      substances_total: substances.size,
      substances_with_reactions: reaction_matrix.size
    },
    substances: []
  }

  reaction_matrix.sort_by { |k, _| k.to_i }.each do |substance_id_str, reagent_entries|
    substance_id = substance_id_str.to_i
    substance = substances[substance_id_str] || {}
    pretty_reagents = []

    reagent_entries.sort_by { |k, _| k.to_i }.each do |reagent_id_str, variants|
      reagent_id = reagent_id_str.to_i
      reagent = reagent_by_id[reagent_id] || {}
      pretty_variants = []

      variants.each_with_index do |variant, idx|
        detailed_color_ids = (variant[0] || []).map(&:to_i)
        simple_color_ids = (variant[1] || []).map(&:to_i)

        pretty_variants << {
          variant_index: idx + 1,
          reacts: !!variant[2],
          result_text: variant[3] || "",
          detailed_color_ids: detailed_color_ids,
          detailed_colors: detailed_color_ids.map { |id| color_by_id[id]["name"] if color_by_id[id] }.compact,
          simple_color_ids: simple_color_ids,
          simple_colors: simple_color_ids.map { |id| color_by_id[id]["name"] if color_by_id[id] }.compact
        }
      end

      pretty_reagents << {
        reagent_id: reagent_id,
        reagent_short: reagent["shortName"] || "",
        reagent_name: reagent["fullName"] || reagent["name"] || "",
        variants: pretty_variants
      }
    end

    output[:substances] << {
      substance_id: substance_id,
      token: substance["token"] || "",
      name: substance["name"] || "",
      common_name: substance["commonName"] || "",
      is_popular: !!substance["isPopular"],
      reagents: pretty_reagents
    }
  end

  output
end

def drugs_pro_scraper
  chunk_url = discover_chunk_url
  chunk_res = fetch_text(chunk_url)

  unless chunk_res[:ok]
    raise "Failed to fetch live analyzer chunk: #{chunk_res[:status]} #{chunk_res[:url]}"
  end

  master = extract_embedded_json(chunk_res[:text])
  output = build_output(master, chunk_url)
  return output
end


def query_protestkit(record)
  data = drugs_pro_scraper

  #search = "Methamphetamine"
  search = [ record["Title"] ]
  search += record["Abbreviation"] if record["Abbreviation"] != nil
  search += record["Aliases"] if record["Aliases"] != nil
  #puts JSON.pretty_generate(data)
  record["Reagents"] = []
  for sub in data[:substances]
    next if not [sub[:token], sub[:name], sub[:common_name]].any? { |v| search.any? { |s| s.downcase == v.downcase } }
    #puts JSON.pretty_generate(sub)
    for reg in sub[:reagents]
      #colors = reg[:variants][0][:detailed_colors].map { |c| c.sub(/\d+$/, '') }
      colors = reg[:variants][0][:detailed_colors].map { |c| color_to_hex(c) }
      puts "#{reg[:reagent_name]}: #{colors}"
      record["Reagents"] << { Name: reg[:reagent_name], Colors: colors }
      #puts JSON.pretty_generate(reg)
    end
  end

  return record
end
