$options = {
  m: "search",
  d: "db.sqlite",
}
$compounds = []
$to_index = []

def skip?(source)
  ($options[:s] || []).include?(source)
end
