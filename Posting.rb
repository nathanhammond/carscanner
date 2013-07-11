class Posting
  attr_reader :id
  attr_reader :updated
  attr_reader :description

  def initialize(scanner, region, domelement)
    # Parse information out of the posting.
    @id = domelement["data-pid"]
    @regionid = region.id
    
    @link = URI("http://#{@regionid}.craigslist.org/cto/#{@id}.html")
    @description = domelement.search(".pl > a").length == 1 ? domelement.search(".pl > a").first.content : nil
    @price = domelement.search("span.price").length == 1 ? domelement.search("span.price").first.content : nil
    @location = domelement.search(".l2 small").length == 1 ? domelement.search(".l2 small").first.content.gsub(/[\(\)]/,'').strip : nil
    @lat = domelement["data-latitude"] ? domelement["data-latitude"].to_f : nil
    @lon = domelement["data-longitude"] ? domelement["data-longitude"].to_f : nil
    @distance = @lat && @lon ? haversine(scanner.lat, scanner.lon, @lat, @lon) : region.distance
    
    # Get the contents of the posting.
    document = Nokogiri::HTML(Net::HTTP.get(@link))
    @body = document.search('#postingbody').first.content

    dates = document.search('.userbody date')
    @created = DateTime.parse(dates.first.content)
    @updated = DateTime.parse(dates.last.content)
    
    @images = []    
    imagelinks = document.search('#thumbs > a')
    if imagelinks.length != 0
      imagelinks.each { |imagelink| @images.push(imagelink.attr('href')) }
    end
    
    @email = document.search('a[href^=mailto]').length == 1 ? document.search('a[href^=mailto]').attr('href') : nil
    
    # TODO: Parse emails and/or phone numbers out of the posting.
  end

  # TODO: Fix JSON output.
  def to_s
    self.to_json
  end
  
  def to_json(ignore)
    hash = {}
    self.instance_variables.each do |var|
        hash[var] = self.instance_variable_get var
    end
    hash.to_json
  end

end