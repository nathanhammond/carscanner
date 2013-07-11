class CLScanner
  attr_reader :lat
  attr_reader :lon
  
  Areas = URI('http://www.craigslist.org/about/areas.json')
  Sites = URI('http://www.craigslist.org/about/sites')

  # For bootstrapping.
  def initialize(lat, lon)
    @lat = lat
    @lon = lon
    @parsedsites = Nokogiri::HTML(Net::HTTP.get(Sites))
    @parsedareas = JSON.parse(Net::HTTP.get(Areas))

    loadcontinents
    loadregions
  end

  def loadcontinents
    @continents = {}
    
    # CL conveniently left us a map.
    @parsedsites.search(".jump_to_continents a").each do |element|
      continent = Continent.new element
      @continents[continent.id] = continent
    end
  end

  def loadregions
    @regions = {}

    # Build the base with the geospatial file.
    @parsedareas.each do |json|
      region = Region.new(self, json)
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
        searchregion(query,region)
        puts "#{hostname} finished by thread #{Thread.current[:id]+1}"
      end
    end
    
    @pool.shutdown
  end

  # TODO: Clean me up!
  def searchregion(query, region)
    @listings = {}
    @cars = {}

    # In case there are multiple pages of results from a search
    pages = []
    pagecount = false

    # Make requests for every page.
    while (pages.length != pagecount)
      # End up with a start of "0" on the first time, 100 is craigslist's page length.
      page = pages.length * 100    

      # Here is the URL we'll be making the request of.
      url = URI("http://#{region.id}.craigslist.org/search/cto?query=#{query}&srchType=T&s=#{page}")

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
        listing = Listing.new(self, region, listing)
        car = Car.new(listing)

        # TODO: check for car/listing updates.
        @listings[listing.id] = listing
        @cars[listing.id] = car
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

    # TODO: Fix the JSON output.
    return output.to_json
  end

end

# TODO:
# Automatically collate identical listings.
# Capture the listing content and contact info.
# Make paging use the thread pool.
# Make getting the listing content use the thread pool.
# Lexically parse the listing content to store information about the car itself.