require 'digest'
require 'httparty'
require 'nokogiri'
require 'json'
require 'erb'

require_relative 'config'

DEFAULT_TIMEOUT = 50
DEFAULT_RETRIES = 3

def perform_request(url, accept, cookies = nil)
  HTTParty.get(
    url.gsub(" ", "%20"),
    timeout: DEFAULT_TIMEOUT,
    headers: { "accept" => accept },
    cookies: cookies
  )
end

def fetch(url, accept, static = nil, cookies = nil)
  puts "Fetch: #{url}" if $options[:v]

  cache_file = nil

  if !$options[:c].nil?
    cache_file = File.join(
      $options[:c],
      Digest::MD5.hexdigest(static || url)
    )

    if File.exist?(cache_file) &&
       File.size(cache_file) > 0 &&
       ((Time.now - File.mtime(cache_file)) / (24 * 60 * 60)) < 5.0

      puts "Load Cache: #{url}" if $options[:v]
      return File.read(cache_file)
    end
  end

  attempts = 0

  begin
    attempts += 1

    response = perform_request(url, accept, cookies)

    return nil unless response.code == 200

    if response.headers['x-throttling-control'] && $options[:v]
      puts response.headers['x-throttling-control']
    end

    File.write(cache_file, response.body) if cache_file

    response.body

  rescue Net::ReadTimeout,
         Net::OpenTimeout,
         Errno::ECONNRESET,
         SocketError,
         HTTParty::Error => e

    if attempts < DEFAULT_RETRIES
      puts "Retry #{attempts}/#{DEFAULT_RETRIES}: #{e.class}" if $options[:v]
      sleep(attempts)
      retry
    end

    puts "Failed: #{url} (#{e.class})" if $options[:v]
    nil
  end
end

def fetch_html(url)
  Nokogiri::HTML(fetch(url, "text/html")) do |config|
    config.strict.noblanks
  end
end

def fetch_xml(url)
  Nokogiri::XML(fetch(url, "application/xml")) do |config|
    config.strict.noblanks
  end
end
