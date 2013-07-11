class Listing
  attr_reader :id
  attr_reader :date
  attr_reader :description

  def initialize(scanner, region, domelement)
    # Parse information out of the listing.
    @id = domelement["data-pid"]
    @regionid = region.id
    @date = domelement.search(".date").length == 1 ? Date.parse(domelement.search(".date").first.content) : nil

    # When Craigslist wraps at the end of the year it doesn't add a year field.
    # Fortunately Craigslist has an approximately one month listing duration which makes it easy to know which year is being referred to.
    # Overshooting by incrementing the month to make sure that timezone differences between this and CL servers don't result in weirdness
    if @date.month > Date.today.month + 1
      @date = @date.prev_year
    end
    
    @link = "http://#{@regionid}.craigslist.org/cto/#{@id}.html"
    @description = domelement.search(".pl > a").length == 1 ? domelement.search(".pl > a").first.content : nil
    @price = domelement.search("span.price").length == 1 ? domelement.search("span.price").first.content : nil
    @location = domelement.search(".l2 small").length == 1 ? domelement.search(".l2 small").first.content.gsub(/[\(\)]/,'').strip : nil
    @lat = domelement["data-latitude"] ? domelement["data-latitude"].to_f : nil
    @lon = domelement["data-longitude"] ? domelement["data-longitude"].to_f : nil
    @distance = @lat && @lon ? haversine(scanner.lat, scanner.lon, @lat, @lon) : region.distance
    
    # TODO: Consider getting the contents of the listing.
  end

  # TODO: Fix JSON output.
  # def to_s
  #   self.to_json
  # end
  # 
  # def to_json
  #   hash = {}
  #   self.instance_variables.each do |var|
  #       hash[var] = self.instance_variable_get var
  #   end
  #   hash.to_json
  # end

end