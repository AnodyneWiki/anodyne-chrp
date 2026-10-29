Gem::Specification.new do |spec|
  spec.name          = "anodyne-chrp"
  spec.version       = "0.1.0"
  spec.summary       = "AnodyneWiki's aggregator scripts"
  spec.authors       = ["AnodyneWiki"]
  spec.files         = Dir["lib/**/*.rb", "exe/*", "assets/*.json", "scripts/stereoisomers.py"]
  spec.bindir        = "exe"
  spec.executables   = ["chrp"]
  spec.require_paths = ["lib"]
  spec.add_dependency "base64"
  spec.add_dependency "builder"
  spec.add_dependency "commonchemistry"
  spec.add_dependency "csv"
  spec.add_dependency "httparty"
  # Pinned to the last release that ships a precompiled x64-mingw32 binary
  # (Ruby 3.0 on Windows). 1.18+ only ships x64-mingw-ucrt and would build from source.
  spec.add_dependency "nokogiri", "~> 1.17.2"
  spec.add_dependency "sqlite3"
  spec.add_dependency "svg_optimizer"
end
