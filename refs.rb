REFS = [
  { name: "Wikipedia", url: "https://en.wikipedia.org/wiki/", key: "Wikipedia", icon: "https://en.wikipedia.org/static/favicon/wikipedia.ico", clean: false },
  { name: "Wikidata", url: "https://www.wikidata.org/wiki/", key: "Wikidata", icon: "https://www.wikidata.org/static/favicon/wikidata.ico", clean: false },
  { name: "Wikitionary", url: "https://www.wikitionary.org/wiki/", key: "Wikitionary", icon: "https://www.wiktionary.org/static/favicon/piece.ico", clean: false },
  { name: "EffectIndex", url: "https://www.effectindex.com/", key: "EffectIndex", icon: "https://www.effectindex.com/_nuxt/icons/icon_64x64.722c40.png", clean: true },
  { name: "EffectIndexAnodyne", url: "/effect/", key: "EffectIndexAnodyne", icon: "https://www.effectindex.com/_nuxt/icons/icon_64x64.722c40.png", clean: true },
  { name: "DrugBank", url: "https://go.drugbank.com/", key: "DrugBank ID", icon: "https://go.drugbank.com/favicons/favicon.ico", clean: true },
  { name: "Erowid", url: "https://www.erowid.org", key: "Erowid", icon: "https://erowid.org/favicon.ico", clean: true },
  { name: "OpenErowid", url: "https://erowid.io", key: "Erowid", icon: "https://sernyl.io/logo-notext-lm.png", clean: true },
  { name: "PubChem", url: "https://pubchem.ncbi.nlm.nih.gov/compound/", key: "PubChemId", icon: "https://pubchem.ncbi.nlm.nih.gov/pcfe/favicon/favicon.ico", clean: false },
  { name: "Sciencemadness", url: "https://www.sciencemadness.org/smwiki/index.php/", key: "ScienceMadness", icon: "https://www.sciencemadness.org/favicon.ico", clean: false },
  { name: "ChemSpider", url: "https://www.chemspider.com/Chemical-Structure.", end: ".html", key: "chemspiderId", icon: "https://www.rsc-cdn.org/oxygen/assets/favicons/favicon-32x32.png", clean: true },
  { name: "ChEMBL", url: "https://www.ebi.ac.uk/chembl/explore/compound/", end: "", key: "ChEMBL", icon: "https://www.ebi.ac.uk/chembl/_nuxt/img/chembl_logo_pink.fa83e6a.png", clean: false },
  { name: "ChEBI", url: "https://www.ebi.ac.uk/chebi/searchId.do?chebiId=", end: "", key: "ChEBI", icon: "https://www.ebi.ac.uk/chebi/images/ChEBI_logo.png", clean: false },
  { name: "Probes & Drugs", url: "https://www.probes-drugs.org/compound/", end: "", key: "PD", icon: "https://www.probes-drugs.org/static/img/pd_logo.svg", clean: false },
  { name: "Common Chemistry", url: "https://commonchemistry.cas.org/detail?cas_rn=", key: "CAS", icon: "https://commonchemistry.cas.org/favicon.png?ver=2", clean: false },
  { name: "Isomer Design", url: "https://isomerdesign.com/", key: "IsomerDesign", icon: "https://isomerdesign.com/favicon.ico", clean: false },
  { name: "HMDB", url: "https://hmdb.ca/metabolites/", key: "HMDB ID", icon: "https://hmdb.ca/assets/favicon-9531cde275d5419775671ec3320c1245747b762c98fb8c2d800f1ddfdb4f42c9.png", clean: false },
  { name: "KEGG", url: "https://www.kegg.jp/entry/", key: "KEGG ID", icon: "https://www.kegg.jp/favicon.ico", clean: true },
  { name: "UNII", url: "https://gsrs.ncats.nih.gov/ginas/app/ui/substances/", key: "UNII", icon: "https://gsrs.ncats.nih.gov/ginas/app/ui/assets/favicon/favicon-32x32.png", clean: false },
  { name: "EPA DSSTox", url: "https://comptox.epa.gov/dashboard/chemical/details/", key: "DSSTox Substance ID", icon: "https://comptox.epa.gov/dashboard/epa_logo.png", clean: true },
  { name: "Github", url: "https://github.com/", icon: "https://github.githubassets.com/favicons/favicon-dark.png", clean: false },
  { name: "Reddit", url: "https://www.reddit.com/", icon: "https://www.redditstatic.com/shreddit/assets/favicon/64x64.png", clean: false },
  { name: "dbi-igs", url: "https://dbi-igs.org/", icon: "https://dbi-igs.org/favicon.ico", clean: true },
  #{ name: "ECHA Chem", url: "https://chem.echa.europa.eu/100.005.543", key: "UNII", clean: true },
]

def generate_references(record)
  references = []
  for ref in REFS
    if record["#{ref[:key]}"] != nil
      references += [
        {Name: ref[:name], Urls: [ { Name: record["Title"], Link: "#{ref[:url]}#{record["#{ref[:key]}"]}#{ref[:end]}", Sub: false } ]}
      ]
      if ref[:clean] == true
        record.delete(ref[:key])
      end
    end
  end
  return references.dup
end
