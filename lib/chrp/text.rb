require 'uri'

def contains_symbols(input)
  !!(input =~ /[αβγΔδ]/)
end

# The last gsub covers anything else URI refuses to parse, e.g. { } in chemical
# names. Spaces are left to fetch()
def encode_symbols(input)
  return input.gsub("α", "%CE%B1").gsub("Α", "%CE%B1").gsub("β", "%CE%B2").gsub("Β", "%CE%B2").gsub("Γ", "%CE%B3").gsub("γ", "%CE%B3").gsub("Δ", "%CE%94").gsub("δ", "%CE%B4").gsub("(", "%28").gsub(")", "%29").gsub("'", "%27").gsub("[", "%5B").gsub("]", "%5D")
    .gsub(/[^A-Za-z0-9\-._~:\/?#\[\]@!$&'()*+,;=% ]/) { |c| URI.encode_www_form_component(c) }
end

def replace_symbols(input)
  return input.gsub("α", "alpha").gsub("β", "beta").gsub("Γ", "gamma").gsub("γ", "gamma").gsub("Δ", "delta").gsub("δ", "delta")
end

def replace_names(input)
  input.gsub("Alpha", "α").gsub("Beta", "β").gsub("Gamma", "γ").gsub("Delta", "Δ")
  .gsub(".alpha.", "α").gsub(".beta.", "β").gsub(".gamma.", "γ").gsub(".delta.", "Δ")
  .gsub("alpha", "α").gsub("beta", "β").gsub("gamma", "γ").gsub("delta", "Δ")
  .gsub(".ALPHA.", "α").gsub(".BETA.", "β").gsub(".GAMMA.", "γ").gsub(".DELTA.", "Δ")
  .gsub("ALPHA", "α").gsub("BETA", "β").gsub("GAMMA", "γ").gsub("DELTA", "Δ")
end
