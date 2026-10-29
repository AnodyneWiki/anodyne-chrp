require_relative '../lib/chrp/protestkit'

# Offline check of the payload extraction, using a chunk shaped like the live ones.
def check(desc, ok, out = "")
  puts "#{ok ? 'ok' : 'FAILED'}: #{desc}"
  return if ok
  puts out
  exit 1
end

payload = %q({"Tj":{"1":{"id":1,"name":"white"}},"aZ":{"7":{"id":7,"shortName":"Si","fullName":"Simon\'s"}},"sE":{"5":{"token":"mdma","name":"MDMA","commonName":"α x"}},"Xv":{"5":{"7":[[[1],[1],true,"blue"]]}}})
chunk = %Q(push([[2238],{1(e,o,a){const q=JSON.parse('{"other":1}');const l=JSON.parse('#{payload}');var r=a(1)}}]))

master = extract_embedded_json(chunk)
check("payload is found regardless of the minified variable name", master.is_a?(Hash) && master.key?("Xv"), master.inspect)
check("escaped quotes are decoded", master["aZ"]["7"]["fullName"] == "Simon's" && master["sE"]["5"]["commonName"] == "\u03b1 x", master.inspect)

out = build_output(master, "https://example.invalid/chunk.js")
reagent = out[:substances][0][:reagents][0]
check("output maps reagents and colors", out[:substances][0][:name] == "MDMA" && reagent[:reagent_name] == "Simon's" && reagent[:variants][0][:detailed_colors] == ["white"], out.inspect)
