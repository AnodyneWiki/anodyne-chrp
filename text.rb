def contains_symbols(input)
  !!(input =~ /[αβγΔδ]/)
end

def encode_symbols(input)
  return input.gsub("α", "%CE%B1").gsub("Α", "%CE%B1").gsub("β", "%CE%B2").gsub("Β", "%CE%B2").gsub("Γ", "%CE%B3").gsub("γ", "%CE%B3").gsub("Δ", "%CE%94").gsub("δ", "%CE%B4").gsub("(", "%28").gsub(")", "%29").gsub("'", "%27")
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
