require 'date'
require 'json'
require 'net/http'
require 'nokogiri'
require './ThreadPool'

def haversine(lat1, long1, lat2, long2)
  dtor = Math::PI/180
  r = 3959
 
  rlat1 = lat1 * dtor
  rlong1 = long1 * dtor
  rlat2 = lat2 * dtor
  rlong2 = long2 * dtor
 
  dlon = rlong1 - rlong2
  dlat = rlat1 - rlat2
 
  a = Math::sin(dlat/2)**2 + Math::cos(rlat1) * Math::cos(rlat2) * Math::sin(dlon/2)**2
  c = 2 * Math::atan2(Math::sqrt(a), Math::sqrt(1-a))
  d = r * c
 
  return d
end

class Continent
  def initialize(domelement)
    @anchor = domelement.attr('href').gsub('#','')
    @name = domelement.content
  end

  def id
    @anchor
  end
  
  def to_s
    @name
  end
end

class Region
  attr_accessor :continent

  def initialize(json, lat, lon)
    json.each do |key,value|
      if ["name","hostname","region","country","lat","lon"].include? key
        instance_variable_set("@#{key}", value)
      end
    end

    @distance = haversine(@lat, @lon, lat, lon)
  end

  def reup(continent, regionname)
    @continent = continent
    @regionname = regionname
  end

  def id
    @hostname
  end
  
  def to_s
    @name
  end
end

class Listing
  attr_reader :id
  attr_reader :date
  attr_reader :description

  def initialize(domelement, regionid)
    # Parse information out of the listing.
    @id = domelement["data-pid"]
    @regionid = regionid
    @date = domelement.search(".date").length == 1 ? Date.parse(domelement.search(".date").first.content) : nil

    # When Craigslist wraps at the end of the year it doesn't add a year field.
    # Fortunately Craigslist has an approximately one month time limit that makes it easy to know which year is being referred to.
    # Overshooting by incrementing the month to make sure that timezone differences between this and CL servers don't result in weirdness
    if @date.month > Date.today.month + 1
      @date = @date.prev_year
    end
    
    @link = "http://#{@regionid}.craigslist.org/cto/#{@id}.html"
    @description = domelement.search(".pl > a").length == 1 ? domelement.search(".pl > a").first.content : nil
    @price = domelement.search("span.price").length == 1 ? domelement.search("span.price").first.content : nil
    @location = domelement.search(".l2 small").length == 1 ? domelement.search(".l2 small").first.content.gsub(/[\(\)]/,'').strip : nil
    @lat = domelement["data-latgitude"]
    @lon = domelement["data-longitude"]

    # TODO
    # @distance = @region[@regionid]
    
    # TODO: Consider getting the contents of the listing.
    @car = Car.new self
  end

  def to_s
    self.to_json
  end

  def to_json
    hash = {}
    self.instance_variables.each do |var|
        hash[var] = self.instance_variable_get var
    end
    hash.to_json
  end

end

# All the properties that are specific to the car. Will have to be parsed out of the listing.
class Car
  attr_reader :year

  def initialize(listing)
    @id = nil
    @listingid = listing.id
    @year = findyear(listing.description)
  end
  
  def findyear(string)
    # Pull car model year from string.
    # Can be wrong, but likely accurate.
    matches = /(?:\b19[0-9]{2}\b|\b20[0-9]{2}\b|\b[0-9]{2}\b)/.match(string)

    if matches.nil?
      year = nil
    elsif matches[0].length == 4
      year = matches[0]
    elsif matches[0].length == 2
      # Not an arbitrary wrapping point like it is in MySQL, etc.
      # Cars have known manufacture dates and can't be too far in the future.
      year = matches[0].to_i <= Date.today.strftime("%y").to_i + 1 ? "20#{matches[0]}" : "19#{matches[0]}"
    end
    
    year
  end

end

class CLScanner
  Areas = URI('http://www.craigslist.org/about/areas.json')
  Sites = URI('http://www.craigslist.org/about/sites')

  # For bootstrapping.
  def initialize(lat, lon)
    @parsedsites = Nokogiri::HTML(Net::HTTP.get(Sites))
    @parsedareas = JSON.parse(Net::HTTP.get(Areas))

    loadcontinents
    loadregions(lat, lon)
  end

  def loadcontinents
    @continents = {}
    
    # CL conveniently left us a map.
    @parsedsites.search(".jump_to_continents a").each do |element|
      continent = Continent.new element
      @continents[continent.id] = continent
    end
  end

  def loadregions(lat, lon)
    @regions = {}

    # Build the base with the geospatial file.
    @parsedareas.each do |json|
      region = Region.new json, lat, lon
      @regions[region.id] = region
    end

    # Extend with continent and text region name from the about page.
    @parsedsites.search("section.body li a").each do |region|
      id = URI.parse(region.attr('href')).host.split(".").first
      regionname = region.parent.parent.previous_element.content
      continent = region.parent.parent.parent.parent.previous_element.search('a').attr('name').to_s

      # There's something funky going on in South Florida.
      # If we don't have a region, don't try.
      @regions[id].reup(continent, regionname) unless @regions[id].nil?
    end
  end

  def search(query, regionswhitelist, continentswhitelist)
    # Set up a thread pool.
    @pool = ThreadPool.new(64)
    at_exit { @pool.shutdown }

    # Iterate over each region and push the processing for it into the processing queue.
    @regions.each do |hostname,region|

      # Scope the search to specified regions and continents
      next unless continentswhitelist.include? region.continent unless continentswhitelist.nil?
      next unless regionswhitelist.include? region.id unless regionswhitelist.nil?

      # Throw the function into the pool.
      @pool.schedule do
        searchregion(query,hostname)
        puts "#{hostname} finished by thread #{Thread.current[:id]+1}"
      end
    end
    
    @pool.shutdown
  end

  # TODO: Clean me up!
  def searchregion(query, regionid)
    @listings = {}

    # In case there are multiple pages of results from a search
    pages = []
    pagecount = false

    # Make requests for every page.
    while (pages.length != pagecount)
      # End up with a start of "0" on the first time, 100 is craigslist's page length.
      page = pages.length * 100    

      # Here is the URL we'll be making the request of.
      url = URI("http://#{regionid}.craigslist.org/search/cto?query=#{query}&srchType=T&s=#{page}")

      # Get the response and parse it.
      pages << Nokogiri::HTML(Net::HTTP.get(url))

      # If this is the first time through
      if (pagecount == false)

        # Check to make sure there are results.
        if pages.last().search('.resulttotal').length != 0
          # There are results, and we need to see if additional requests are necessary.
          pagecount = (pages.last().search('.resulttotal').first.content.gsub(/[^0-9]/,'').to_i / 100.0).ceil
        end
      end
    end

    # Go through each results page and process the listings.
    pages.each do |page|
      page.search('.row').each do |listing|
        # Skip listings from other regions in case there are any. ("FEW LOCAL RESULTS FOUND")
        next if listing.search('a[href^=http]').length != 0
        listing = Listing.new(listing, regionid)

        # TODO: check for listing updates.
        @listings[listing.id] = listing
      end
    end
  end

  def to_s
    output = @listings.values.sort { |a,b|
      if a.date == b.date
        b.id.to_i <=> a.id.to_i
      else
        b.date <=> a.date
      end
    }
    
    return output.to_s
  end

end

scanner = CLScanner.new 35.23308, -80.805521
scanner.search("TDI", ["albany", "charlotte"], ["US"])
puts scanner