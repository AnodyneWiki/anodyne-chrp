require 'uri'

require_relative '../lib/chrp/text'

def check(desc, ok, out = "")
  puts "#{ok ? 'ok' : 'FAILED'}: #{desc}"
  return if ok
  puts out
  exit 1
end

name = "3-(4-{2-[Bis(4-fluorophenyl)methoxy]ethyl}-1-piperazinyl)-1-phenylpropyl decanoate"
url = encode_symbols("https://rest.kegg.jp/find/drug/#{name}").gsub(" ", "%20")
check("braces in a name give a parseable URL", (URI.parse(url) rescue nil) && url.include?("%7B2-") && url.include?("ethyl%7D"), url)

url = encode_symbols("https://example.invalid/a|b^c\"d<e>f`g\\h/é")
check("other characters URI rejects are encoded", (URI.parse(url) rescue nil) && url.end_with?("/%C3%A9"), url)

url = "https://example.invalid/find/drug/Aspirin%20x?q=a&b=c+d#frag"
check("valid URLs are left alone", encode_symbols(url) == url, encode_symbols(url))

check("greek letters and brackets are encoded as before", encode_symbols("α-(β)['x']") == "%CE%B1-%28%CE%B2%29%5B%27x%27%5D", encode_symbols("α-(β)['x']"))
