require 'json'
require_relative 'fetch'

MESH_URL = "https://id.nlm.nih.gov/"

def query_mesh(record)
  return record
  return {} if record == nil
  json_fetch = fetch("#{MESH_URL}mesh/lookup/descriptor?match=exact&limit=10&label=#{record['Title']}", "application/json")
  return record if json_fetch == nil

  lookup = JSON.parse(json_fetch)
  return record if lookup == nil

  #puts JSON.pretty_generate(lookup)
  resource = lookup[0]["resource"]
  entry = resource.split('/').last
  neturn record if resource == nil

  qualifiers_fetch = fetch("#{MESH_URL}mesh/lookup/qualifiers?descriptor=#{entry}", "application/json")
  return record if qualifiers_fetch == nil

  qualifiers = JSON.parse(qualifiers_fetch)
  return record if qualifiers == nil or qualifiers.empty?
  qualifiers.each do |qual|
    qal_fetch = fetch("#{MESH_URL}mesh/#{qual}.json", "application/json")
    next if qal_fetch == nil
    qal = JSON.parse(qal_fetch)
    next if qal == nil

    #puts qal["annotation"]["@value"] if qal["annotation"] != nil and qal["annotation"]["@value"] != nil
  end

  mesh_fetch = fetch("#{MESH_URL}mesh/#{entry}.json", "application/json")
  return record if mesh_fetch == nil

  mesh = JSON.parse(fetch("#{MESH_URL}mesh/#{entry}.json", "application/json"))
  puts "annotation: #{mesh['annotation']['@value']}"
  puts "lastUpdated: #{mesh['lastUpdated']['@value']}"
  puts "pharmacologicalAction: #{mesh['pharmacologicalAction'].map { |act| act.split('/').last }.join(', ')}"
  puts "concept: #{mesh['concept'].map { |act| act.split('/').last }.join(', ')}"
  puts "allowableQualifier: #{mesh['allowableQualifier'].map { |act| act.split('/').last }.join(', ')}"
  puts "tree: #{mesh['treeNumber']}"

  return record
end
