require 'json'

$reddit_data = nil

def query_reddit(record)
  if $reddit_data.nil?
    file_path = File.join(File.dirname(__FILE__), 'reddit_test.json')
    if File.exist?(file_path)
      puts "Loading #{file_path} into memory..."
      begin
        $reddit_data = JSON.parse(File.read(file_path))
      rescue => e
        puts "Error loading reddit_test.json: #{e.message}"
        $reddit_data = []
      end
    else
      puts "Warning: #{file_path} not found."
      $reddit_data = []
    end
  end

  return record if $reddit_data.empty?

  # Collect all possible names for this substance
  search_terms = []
  search_terms << record["Title"] if record["Title"]
  
  if record["Abbreviation"]
    if record["Abbreviation"].is_a?(Array)
      search_terms += record["Abbreviation"]
    else
      search_terms << record["Abbreviation"]
    end
  end

  if record["Aliases"]
    if record["Aliases"].is_a?(Array)
      search_terms += record["Aliases"]
    else
      search_terms << record["Aliases"]
    end
  end

  search_terms = search_terms.compact.map(&:downcase).uniq

  # Filter reports where any mentioned substance matches our search terms
  matches = $reddit_data.select do |report|
    next false unless report["substances"]
    report["substances"].any? { |sub| search_terms.include?(sub.downcase) }
  end

  # Sort by score (upvotes) descending
  matches.sort_by! { |r| -(r["score"] || 0) }

  record["Reddit Experience Reports"] = matches
  
  puts "Found #{matches.length} Reddit reports for #{record["Title"]}" if matches.length > 0

  return record
end
