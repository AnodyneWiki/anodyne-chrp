require 'sqlite3'
require 'builder'
require 'date'

BASE_URL = "https://anodyne.wiki"

def slugify(title)
  title.downcase
       .gsub(/[^a-z0-9]+/, '-') # replace non-alphanum with dashes
       .gsub(/^-|-$/, '')       # trim leading/trailing dashes
end

STATIC_URLS = [
  "#{BASE_URL}/",
  "#{BASE_URL}/about",
  "#{BASE_URL}/donate",
  "#{BASE_URL}/legal",
  "#{BASE_URL}/quotes",
  "#{BASE_URL}/api",
  "#{BASE_URL}/index/administration",
  "#{BASE_URL}/index/substance",
  "#{BASE_URL}/index/user"
]

def generate_sitemap(db)
  File.open("sitemap.xml", "w") do |file|
    xml = Builder::XmlMarkup.new(:target => file, :indent => 2)
    xml.instruct! :xml, :version => "1.0", :encoding => "UTF-8"

    xml.urlset("xmlns" => "http://www.sitemaps.org/schemas/sitemap/0.9") do
      # --- Static entries ---
      STATIC_URLS.each do |url|
        xml.url do
          xml.loc url
          xml.lastmod Date.today.iso8601
          xml.changefreq "monthly"
          xml.priority "0.8"
        end
      end

      Dir.glob("index/*.json") do |idx|
        filename = File.basename(idx, ".json")
        slug = slugify(filename)

        lastmod = File.mtime(idx).to_date.iso8601

        xml.url do
          xml.loc "#{BASE_URL}/index/#{slug}"
          xml.lastmod lastmod
          xml.changefreq "monthly"
          xml.priority "0.5"
        end
      end
      Dir.glob("effect/*.md") do |eff_md|
        filename = File.basename(eff_md, ".md")
        slug = slugify(filename)

        lastmod = File.mtime(eff_md).to_date.iso8601

        xml.url do
          xml.loc "#{BASE_URL}/effect/#{slug}"
          xml.lastmod lastmod
          xml.changefreq "monthly"
          xml.priority "0.5"
        end
      end
      Dir.glob("administration/*.md") do |roa_md|
        filename = File.basename(roa_md, ".md")
        slug = slugify(filename)

        lastmod = File.mtime(roa_md).to_date.iso8601

        xml.url do
          xml.loc "#{BASE_URL}/administration/#{slug}"
          xml.lastmod lastmod
          xml.changefreq "monthly"
          xml.priority "0.5"
        end
      end
      Dir.glob("user/*") do |user|
        filename = File.basename(user)
        slug = slugify(filename)

        lastmod = File.mtime(user).to_date.iso8601

        xml.url do
          xml.loc "#{BASE_URL}/user/#{slug}"
          xml.lastmod lastmod
          xml.changefreq "monthly"
          xml.priority "0.5"
        end
      end
      Dir.glob("substituted/*.json") do |json_file|
        filename = File.basename(json_file, ".json")
        slug = slugify(filename)

        lastmod = File.mtime(json_file).to_date.iso8601

        xml.url do
          xml.loc "#{BASE_URL}/substituted/#{slug}"
          xml.lastmod lastmod
          xml.changefreq "monthly"
          xml.priority "0.5"
        end
      end
      Dir.glob("class/*.json") do |json_file|
        filename = File.basename(json_file, ".json")
        slug = slugify(filename)

        lastmod = File.mtime(json_file).to_date.iso8601

        xml.url do
          xml.loc "#{BASE_URL}/class/#{slug}"
          xml.lastmod lastmod
          xml.changefreq "monthly"
          xml.priority "0.5"
        end
      end
      db.results_as_hash = true
      db.execute("SELECT title FROM substances") do |row|
        slug = slugify(row["title"])
        #lastmod = row["updated_at"] ? Date.parse(row["updated_at"].to_s).iso8601 : Date.today.iso8601
        lastmod = Date.today.iso8601

        xml.url do
          xml.loc "#{BASE_URL}/substance/#{slug}"
          xml.lastmod lastmod
          xml.changefreq "monthly"
          xml.priority "0.6"
        end
      end
    end
  end
end
