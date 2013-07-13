class CLScanner
  attr_accessor :pool
  
  Areas = URI('http://www.craigslist.org/about/areas.json')
  Sites = URI('http://www.craigslist.org/about/sites')

  # For bootstrapping.
  def initialize
    @continents = {}
    @regions = {}

    @postings = {}

    # Bootstrap the initial information we need for the scanner.
    @parsedsites = Nokogiri::HTML(Net::HTTP.get(Sites))
    @parsedareas = JSON.parse(Net::HTTP.get(Areas))
    loadcontinents
    loadregions

    # Set up a thread pool.
    @pool = ThreadPool.new(64)
  end

  def loadcontinents
    # CL conveniently left us a map.
    @parsedsites.search(".jump_to_continents a").each do |element|
      continent = Continent.new element
      @continents[continent.id] = continent
    end
  end

  def loadregions
    # Build the base with the geospatial file.
    @parsedareas.each do |json|
      region = Region.new(json)
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

  def populate(query, regionswhitelist, continentswhitelist)
    # Iterate over each region and push the processing for it into the processing queue.
    @regions.each do |hostname,region|

      # Scope the search to specified regions and continents
      next unless continentswhitelist.include? region.continent unless continentswhitelist.nil?
      next unless regionswhitelist.include? region.id unless regionswhitelist.nil?

      searchregion(query,region)
    end
  end

  def getresultspage(query, region, page = 0)
    page = page * 100
    url = URI("http://#{region.id}.craigslist.org/search/cto?query=#{query}&srchType=T&s=#{page}")
    
    # yield Nokogiri::HTML(Net::HTTP.get(url))
    @pool.schedule do
      puts "#{url} started by thread #{Thread.current[:id]}"
      result = Nokogiri::HTML(Net::HTTP.get(url))
      puts "#{url} finished by thread #{Thread.current[:id]}"
      yield result
    end
  end

  def processresultspage(region, document)
    document.search('.row').each do |posting|
      # Skip postings from other regions in case there are any. ("FEW LOCAL RESULTS FOUND")
      next if posting.search('a[href^=http]').length != 0
      posting = Posting.new(self, region, posting)

      # TODO: Run a diff on any change.
      @postings[posting.id] = posting
    end
  end

  def searchregion(query, region)
    # First time through is a fishing expedition.
    getresultspage(query, region) do |document|
      # If we have results process them.
      if document.search('.resulttotal').length != 0
        processresultspage(region, document)

        # Calculate remaining pages.
        remainingpagecount = (document.search('.resulttotal').first.content.gsub(/[^0-9]/,'').to_i / 100.0).ceil - 1
        
        # Make any additional requests necessary.
        (1..remainingpagecount).each do |page|
          getresultspage(query, region, page) { |document| processresultspage(region, document) }
        end
      end
    end
  end

  def regions
    return @regions.to_json
  end

  def filter
    # Filter through all stored results
    # output = @postings.values.sort { |a,b|
    #   begin
    #     return a.updated == b.updated ? b.id.to_i <=> a.id.to_i : b.updated <=> a.updated
    #   rescue
    #     pp $!
    #   end
    # }
    return @postings.to_json
  end
  
end

# TODO:
# Make all HTTP requests use a thread pool.
# Provide a user interface.
# Automatically collate identical postings.
# Lexically parse the posting content to store information about the car itself.