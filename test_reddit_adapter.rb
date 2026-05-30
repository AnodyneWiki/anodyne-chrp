require_relative 'reddit'
require 'json'

# Mock record for testing
test_record = {
  "Title" => "LSD",
  "Abbreviation" => ["acid"],
  "Aliases" => ["1P-LSD"]
}

puts "--- Starting Standalone Reddit Adapter Test ---"
puts "Testing with substance: #{test_record["Title"]}"

# Run the adapter
updated_record = query_reddit(test_record)

reports = updated_record["Reddit Experience Reports"]

if reports && reports.length > 0
  puts "\nSUCCESS! Found #{reports.length} reports."
  puts "\nTop 3 Reports (Sorted by Score):"
  reports.first(3).each_with_index do |report, i|
    puts "#{i+1}. [Score: #{report["score"]}] #{report["title"]}"
    puts "   URL: #{report["url"]}"
    puts "   Substances detected: #{report["substances"].join(', ')}"
  end
else
  puts "\nFAILED: No reports found. Check if reddit_test.json is in the current directory."
end

puts "\n--- Test Complete ---"
