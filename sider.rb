require 'cgi'
require 'json'
require 'nokogiri'
require 'httparty'

SIDER_BASE_URL = 'http://sideeffects.embl.de'.freeze

class SIDERScraper
  attr_reader :confidence_logs, :sider_drugs, :alias_map

  def initialize(use_pt: false)
    @use_pt = use_pt
    @confidence_logs = []
    load_local_index
  end

  def get(url, options = {})
    HTTParty.get(url, {
      timeout: 15,
      headers: {
        'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
      }
    }.merge(options))
  rescue StandardError
    nil
  end

  def post(url, options = {})
    HTTParty.post(url, {
      timeout: 10,
      headers: {
        'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
      }
    }.merge(options))
  rescue StandardError
    nil
  end

  def load_local_index
    @alias_map = {}
    @sider_drugs = {}
    @psychoactive_names = []
    @slang_map = {}

    index_path = File.join(File.dirname(__FILE__), 'sider_index.json')
    unless File.exist?(index_path)
      warn "Warning: SIDER index file '#{index_path}' not found. Falling back to live resolution only."
      return
    end

    data = JSON.parse(File.read(index_path, encoding: 'utf-8'))
    @alias_map = data.fetch('alias_map', {})
    @sider_drugs = data.fetch('sider_drugs', {})

    @alias_map.each do |aliaz, entry|
      if entry['is_psychoactive']
        @psychoactive_names << aliaz.downcase
        @psychoactive_names << entry['canonical_name'].downcase if entry['canonical_name']
      end

      sider_name = entry['sider_name']
      @slang_map[aliaz.downcase] = sider_name.downcase if sider_name && aliaz != sider_name
    end
    @psychoactive_names.uniq!
  rescue StandardError => e
    warn "Warning: Failed to load SIDER index file '#{index_path}': #{e.message}"
    @alias_map = {}
    @sider_drugs = {}
  end

  def candidate_labels(document)
    document.css('h4').map { |h4| h4.text.strip }.reject { |text| text.empty? || text.downcase == 'color scheme:' }
  end

  def calculate_confidence(aliaz, drug_name, label_names = [])
    alias_lower = aliaz.downcase
    target_substance = @slang_map.fetch(alias_lower, alias_lower)
    drug_name_lower = drug_name.downcase
    labels_lower = label_names.map(&:downcase)

    score = 0
    reasons = []

    if drug_name_lower == target_substance
      score += 80
      reasons << 'Exact match to target substance'
    elsif drug_name_lower == alias_lower
      score += 75
      reasons << 'Exact match to query alias'
    elsif drug_name_lower.include?(target_substance) || target_substance.include?(drug_name_lower)
      score += 55
      reasons << 'Substring/word overlap with target substance'
    end

    label_exact = false
    label_substring = false
    labels_lower.each do |label|
      parts = label.split(%r{[/,]}).map(&:strip)
      if parts.include?(alias_lower) || parts.include?(target_substance)
        label_exact = true
      elsif label.include?(alias_lower) || label.include?(target_substance)
        label_substring = true
      end
    end

    if label_exact
      score = [score, 80].max
      reasons << 'Exact match to product label name component'
    elsif label_substring
      score = [score, 55].max
      reasons << 'Substring match in product label name'
    end

    is_psychoactive = @psychoactive_names.include?(drug_name_lower) || labels_lower.any? do |label|
      label.scan(/[a-zA-Z0-9-]+/).any? { |word| @psychoactive_names.include?(word) }
    end

    if is_psychoactive
      score += 20
      reasons << 'Psychoactive drug index bonus (+20)'
    end

    if reasons.empty?
      score = 0
      reasons << 'No match'
    end

    [[score, 100].min, reasons.join('; ')]
  end

  def resolve_drug_url(aliaz)
    alias_lower = aliaz.downcase
    @confidence_logs = []

    if @alias_map.key?(alias_lower)
      entry = @alias_map[alias_lower]
      url = "#{SIDER_BASE_URL}/drugs/#{entry['sider_id']}/"
      score = entry['is_psychoactive'] ? 100 : 95
      @confidence_logs << {
        'name' => entry['sider_name'],
        'url' => url,
        'score' => score,
        'reason' => "Exact match found in offline index (is_psychoactive=#{entry['is_psychoactive']})",
        'method' => 'Offline Index (exact)'
      }
      return [url, score]
    end

    candidates = offline_candidates(alias_lower)
    if candidates.any?
      @confidence_logs = candidates
      top_candidate = candidates.first
      return [top_candidate['url'], top_candidate['score']] if top_candidate['score'] >= 70
    end

    redirect_url = direct_redirect_url(aliaz)
    if redirect_url
      resolved = verify_redirect(aliaz, redirect_url)
      return resolved if resolved
    end

    live_candidates = search_box_candidates(aliaz)
    if live_candidates.empty?
      return [redirect_url, @confidence_logs.first['score']] if redirect_url && @confidence_logs.any?

      return [nil, 0]
    end

    evaluated_candidates = evaluate_live_candidates(aliaz, live_candidates)
    @confidence_logs = evaluated_candidates
    top_candidate = evaluated_candidates.first
    return [top_candidate['url'], top_candidate['score']] if top_candidate && top_candidate['score'] >= 50

    [nil, 0]
  end

  def offline_candidates(alias_lower)
    @alias_map.each_with_object([]) do |(name, entry), candidates|
      next unless name.start_with?(alias_lower) || name.include?(alias_lower)

      score = name.start_with?(alias_lower) ? 65 : 45
      reasons = [name.start_with?(alias_lower) ? 'Prefix match in offline index' : 'Substring match in offline index']

      if entry['is_psychoactive']
        score += 20
        reasons << 'Psychoactive drug bonus (+20)'
      end

      candidates << {
        'name' => entry['sider_name'],
        'url' => "#{SIDER_BASE_URL}/drugs/#{entry['sider_id']}/",
        'score' => [score, 100].min,
        'reason' => reasons.join('; '),
        'method' => 'Offline Index (partial)'
      }
    end.sort_by { |candidate| -candidate['score'] }
  end

  def direct_redirect_url(aliaz)
    response = post(SIDER_BASE_URL, body: { q: aliaz }, follow_redirects: true)
    return nil unless response && response.request&.last_uri.to_s.include?('/drugs/')

    url = response.request.last_uri.to_s
    url.end_with?('/') ? url : "#{url}/"
  end

  def verify_redirect(aliaz, redirect_url)
    sider_id = redirect_url[%r{/drugs/(\d+)}, 1]
    if sider_id && @sider_drugs.key?(sider_id)
      drug_info = @sider_drugs[sider_id]
      score = 80 + (drug_info['is_psychoactive'] ? 20 : 0)
      @confidence_logs << {
        'name' => drug_info['sider_name'],
        'url' => redirect_url,
        'score' => score,
        'reason' => "Direct redirect validated via local drug database (is_psychoactive=#{drug_info['is_psychoactive']})",
        'method' => 'Direct Redirect + Local Verify'
      }
      return [redirect_url, score] if score >= 80
    end

    response = get(redirect_url)
    return nil unless response&.code == 200

    document = Nokogiri::HTML(response.body)
    drug_name = document.at_css('h1')&.text&.strip || 'Unknown'
    score, reason = calculate_confidence(aliaz, drug_name, candidate_labels(document))
    @confidence_logs << {
      'name' => drug_name,
      'url' => redirect_url,
      'score' => score,
      'reason' => reason,
      'method' => 'Direct Redirect + Page Verify'
    }
    return [redirect_url, score] if score >= 80

    nil
  rescue StandardError
    nil
  end

  def search_box_candidates(aliaz)
    response = get("#{SIDER_BASE_URL}/searchBox/?q=#{CGI.escape(aliaz)}")
    return [] unless response&.code == 200

    document = Nokogiri::HTML(response.body)
    document.css('ul.drugList li a').map do |link|
      href = link['href']
      next if href.nil? || href.empty?

      { 'name' => link.text.strip, 'url' => href.start_with?('/') ? "#{SIDER_BASE_URL}#{href}" : href }
    end.compact
  rescue StandardError
    []
  end

  def evaluate_live_candidates(aliaz, live_candidates)
    evaluated = live_candidates.map do |candidate|
      existing = @confidence_logs.find { |entry| entry['url'] == candidate['url'] }
      next existing if existing

      verified = local_candidate_score(aliaz, candidate)
      next verified if verified

      score, reason = calculate_confidence(aliaz, candidate['name'])
      {
        'name' => candidate['name'],
        'url' => candidate['url'],
        'score' => score,
        'reason' => reason,
        'method' => 'Search Box (preliminary)'
      }
    end.compact.sort_by { |candidate| -candidate['score'] }

    evaluated.first(3).each do |candidate|
      next if candidate['method'].include?('Verify') || candidate['score'] == 100

      response = get(candidate['url'])
      next unless response&.code == 200

      document = Nokogiri::HTML(response.body)
      score, reason = calculate_confidence(aliaz, candidate['name'], candidate_labels(document))
      candidate['score'] = score
      candidate['reason'] = reason
      candidate['method'] = 'Search Box (refined with labels)'
    rescue StandardError
      next
    end

    evaluated.sort_by { |candidate| -candidate['score'] }
  end

  def local_candidate_score(aliaz, candidate)
    candidate_id = candidate['url'][%r{/drugs/(\d+)}, 1]
    return nil unless candidate_id && @sider_drugs.key?(candidate_id)

    drug_info = @sider_drugs[candidate_id]
    alias_lower = aliaz.downcase
    score = 0
    reasons = []

    if drug_info['sider_name'] == alias_lower
      score += 80
      reasons << 'Exact name match in local verify'
    elsif drug_info['sider_name'].start_with?(alias_lower)
      score += 60
      reasons << 'Prefix name match in local verify'
    end

    if drug_info['is_psychoactive']
      score += 20
      reasons << 'Psychoactive drug bonus (+20)'
    end

    {
      'name' => drug_info['sider_name'],
      'url' => candidate['url'],
      'score' => [score, 100].min,
      'reason' => reasons.join('; '),
      'method' => 'Search Box + Local Verify'
    }
  end

  def scrape_drug_data(url)
    if @use_pt && !url.end_with?('/pt')
      url = "#{url.delete_suffix('/')}/pt"
    end

    response = get(url)
    raise "Failed to fetch page: #{url} (status code #{response&.code || 'none'})" unless response&.code == 200

    document = Nokogiri::HTML(response.body)
    drug_name = document.at_css('h1')&.text&.strip || 'Unknown Drug'
    side_effects = []
    indications = []

    document.css('div.boxDiv').each do |div|
      header = div.at_css('h3')&.text.to_s
      is_side_effects = header.include?('Side effects')
      is_indications = header.include?('Indications')
      next unless is_side_effects || is_indications

      div.css('table tr.bg1, table tr.bg2').each do |row|
        link = row.at_css('td:first-child a')
        next unless link

        clean_link = Nokogiri::HTML.fragment(link.to_html)
        clean_link.css('small').remove
        entry = {
          'name' => clean_link.text.strip,
          'umls_cui' => link['href'].to_s[/C\d{7}/].to_s
        }

        is_side_effects ? side_effects << entry : indications << entry
      end
    end

    {
      'drug_name' => drug_name,
      'url' => url,
      'side_effects' => side_effects.uniq,
      'indications' => indications.uniq
    }
  end

  def scrape_by_aliases(aliases)
    aliases.each do |aliaz|
      url, score = resolve_drug_url(aliaz)
      next unless url

      begin
        data = scrape_drug_data(url)
        data['resolved_alias'] = aliaz
        data['confidence_score'] = score
        data['confidence_logs'] = @confidence_logs

        sider_id = url[%r{/drugs/(\d+)}, 1]
        if sider_id && @sider_drugs.key?(sider_id)
          drug_info = @sider_drugs[sider_id]
          data['atc_codes'] = drug_info.fetch('atc_codes', [])
          data['canonical_name'] = drug_info['canonical_name'] || drug_info['sider_name'].capitalize
          data['is_psychoactive'] = drug_info.fetch('is_psychoactive', false)
        else
          data['atc_codes'] = []
          data['canonical_name'] = data['drug_name']
          data['is_psychoactive'] = false
        end

        return data
      rescue StandardError => e
        warn "Warning: Failed to scrape resolved URL #{url} for alias '#{aliaz}': #{e.message}"
      end
    end

    nil
  end
end

def sider_search_terms(record)
  terms = []
  terms << record['Title']

  %w[Abbreviation Aliases Slang Brands].each do |key|
    value = record[key]
    next if value.nil?

    value.is_a?(Array) ? terms.concat(value) : terms << value
  end

  terms.compact.map(&:to_s).map(&:strip).reject(&:empty?).uniq
end

def query_sider(record)
  return record if record.nil?

  searches = sider_search_terms(record)
  return record if searches.empty?

  data = SIDERScraper.new(use_pt: true).scrape_by_aliases(searches)
  return record if data.nil? || data['side_effects'].empty?

  record['Medical Side Effects'] = {
    'Source' => 'SIDER',
    'Drug Name' => data['drug_name'],
    'Canonical Name' => data['canonical_name'],
    'Resolved Alias' => data['resolved_alias'],
    'Confidence Score' => data['confidence_score'],
    'URL' => data['url'],
    'ATC Codes' => data['atc_codes'],
    'Side Effects' => data['side_effects'],
    'Indications' => data['indications']
  }

  puts "Found #{data['side_effects'].length} SIDER medical side effects for #{record['Title']}"
  record
end

if __FILE__ == $PROGRAM_NAME
  aliases = ARGV.reject { |arg| arg.start_with?('--') }
  use_pt = ARGV.include?('--pt')
  json_output = ARGV.include?('--json')
  debug = ARGV.include?('--debug')

  if aliases.empty?
    warn 'Usage: ruby sider.rb [--pt] [--json] [--debug] ALIAS [ALIAS...]'
    exit 1
  end

  scraper = SIDERScraper.new(use_pt: use_pt)
  data = scraper.scrape_by_aliases(aliases)
  unless data
    warn "Error: Could not resolve any of the aliases: #{aliases.join(', ')}"
    scraper.confidence_logs.first(5).each do |candidate|
      warn "  - #{candidate['name']} (#{candidate['url']}): Score #{candidate['score']}/100 - #{candidate['reason']} [#{candidate['method']}]"
    end
    exit 1
  end

  if json_output
    if debug
      data = data.dup
      data['truncated_counts'] = {
        'side_effects_omitted' => [data['side_effects'].length - 5, 0].max,
        'indications_omitted' => [data['indications'].length - 5, 0].max
      }
      data['side_effects'] = data['side_effects'].first(5)
      data['indications'] = data['indications'].first(5)
      data['db_statistics'] = {
        'total_sider_drugs' => scraper.sider_drugs.length,
        'total_alias_mappings' => scraper.alias_map.length
      }
      data['other_matches'] = scraper.confidence_logs[1, 3]
    end
    puts JSON.pretty_generate(data)
  else
    warn "Resolved '#{data['resolved_alias']}' to '#{data['drug_name']}' (Confidence: #{data['confidence_score']}/100)"
    puts "Drug Name: #{data['drug_name']}"
    puts "Canonical Name: #{data['canonical_name']}"
    puts "Resolved via Alias: #{data['resolved_alias']}"
    puts "SIDER Page URL: #{data['url']}"
    puts "ATC Codes: #{data['atc_codes'].empty? ? 'None' : data['atc_codes'].join(', ')}"
    puts "\n--- Side Effects ---"
    side_effects = debug ? data['side_effects'].first(5) : data['side_effects']
    side_effects.each { |entry| puts "- #{entry['name']} (UMLS: #{entry['umls_cui']})" }
    puts "- ... (and #{data['side_effects'].length - 5} more side effects)" if debug && data['side_effects'].length > 5
    puts "\n--- Indications ---"
    indications = debug ? data['indications'].first(5) : data['indications']
    indications.each { |entry| puts "- #{entry['name']} (UMLS: #{entry['umls_cui']})" }
    puts "- ... (and #{data['indications'].length - 5} more indications)" if debug && data['indications'].length > 5
  end
end
