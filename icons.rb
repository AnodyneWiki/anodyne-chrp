require_relative 'refs'

def generate_icon_css()
  css = ""
  REFS.each do |ref|
    if ref[:icon] != nil
      css += "a.logo[href *='#{ref[:url]}'] { background: url('/icons/#{ref[:name].downcase.gsub(" ", "_")}.ico') center right no-repeat; background-size: 16px; padding-right: 18px }\n"
    end
    icon = HTTParty.get(ref[:icon], verify: false)
    if icon.code == 200
      File.write("icons/#{ref[:name].downcase.gsub(" ", "_")}.ico", icon.body)
    end
  end
  File.write('css/icons.css', css)
end
