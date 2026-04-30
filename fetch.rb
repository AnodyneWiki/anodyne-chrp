require 'digest'
require 'httparty'
require 'nokogiri'
require 'json'
require "erb"

require_relative 'config'

def fetch(url, accept, static = nil)
  if $options[:v]
    puts "Fetch: " + url
  end

  if $options[:c].nil?
    response = HTTParty.get(url.gsub(" ", "%20"), timeout: 50, headers: { "accept" => accept} )
    if response.code != 200
      return nil
    end
    return response.body
  end

  cff = $options[:c] + "/" + Digest::MD5.hexdigest(static != nil ? static : url)
  if File.exist?(cff) && File.size(cff) > 0 && ((Time.now - File.mtime(cff)) / (24 * 60 * 60)) < 5.0
    if $options[:v]
      puts "Load Cache: " + url
    end
    return File.read(cff)
  end

  response = HTTParty.get(url.gsub(" ", "%20"), timeout: 50, headers: { "accept" => accept} )

  if response.code != 200
    return nil
  end

  puts response.headers['x-throttling-control']

  File.write(cff, response.body)
  return response.body
end

def fetch_html(url)
  return Nokogiri::HTML(fetch(url, "text/html")) do |config|
    config.strict.noblanks
  end
end
def fetch_xml(url)
  return Nokogiri::XML(fetch(url, "application/xml")) do |config|
    config.strict.noblanks
  end
end
#def fetch_json(url)
#  return JSON.parse(fetch(url, "application/json"))
#end
