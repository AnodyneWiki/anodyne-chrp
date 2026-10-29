require 'nokogiri'

HMDB_URL = "https://hmdb.ca/metabolites/"
HMDB_URL_END = ".xml"

def query_hmdb(prev_record)
  if prev_record == nil
    record = {}
  else
    record = prev_record
  end
  if record["HMDB ID"] == nil
    return record
  end

  url = HMDB_URL + record["HMDB ID"] + HMDB_URL_END
  xml_fetch = fetch(url, "application/xml")
  if xml_fetch == nil
    return record
  end
  xml_doc = Nokogiri::XML(xml_fetch)

  metabolite = xml_doc.xpath('/metabolite').map do |node| {
    name:    node.at_xpath('name')&.text,
    synonyms: node.xpath('synonyms/synonym').map(&:text),
    direct_substituent: node.at_xpath('taxonomy/direct_parent')&.text,
    substituents: node.xpath('taxonomy/substituents/substituent').map(&:text),
    chemical_formula: node.at_xpath('chemical_formula')&.text,
    average_molecular_weight:    node.at_xpath('average_molecular_weight')&.text.to_f,
    iupac_name:    node.at_xpath('iupac_name')&.text,
    cas_registry_number:    node.at_xpath('cas_registry_number')&.text,
    smiles:    node.at_xpath('smiles')&.text,
    inchi:    node.at_xpath('inchi')&.text,
    inchikey:    node.at_xpath('inchikey')&.text,
    proteins:    node.xpath('protein_associations/protein').map do |node|
      node.elements.map { |el| [el.name.to_sym, el.text] }.to_h
    end,
    biospecimens:    node.xpath('//biospecimen_locations/biospecimen').map(&:text),
    tissue:    node.xpath('//tissue_locations/tissue').map(&:text),
    drugbank_id:    node.at_xpath('drugbank_id')&.text,
    chemspider_id:    node.at_xpath('chemspider_id')&.text,
    pubchem_compound_id:    node.at_xpath('pubchem_compound_id')&.text,
    chebi_id:    node.at_xpath('chebi_id')&.text,
    pdb_id:    node.at_xpath('pdb_id')&.text,
    kegg_id:    node.at_xpath('kegg_id')&.text,
    wikipedia_id:    node.at_xpath('wikipedia_id')&.text
  } end
  record["HMDB Metabolite"] = metabolite

  return record
end
