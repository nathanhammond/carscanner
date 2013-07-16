class Posting
  attr_reader :id
  attr_reader :updated
  attr_reader :title
  attr_reader :car

  def initialize(scanner, region, domelement)
    # Parse information out of the posting.
    @id = domelement["data-pid"]
    @regionid = region.id
    @active = nil

    @link = domelement.search(".pl > a").length == 1 ? URI("http://#{@regionid}.craigslist.org" + domelement.search(".pl > a").first.attr('href')) : nil
    @title = domelement.search(".pl > a").length == 1 ? domelement.search(".pl > a").first.content : nil
    @price = domelement.search("span.price").length == 1 ? domelement.search("span.price").first.content : nil
    @location = domelement.search(".l2 small").length == 1 ? domelement.search(".l2 small").first.content.gsub(/[\(\)]/,'').strip : nil
    @lat = domelement["data-latitude"] ? domelement["data-latitude"].to_f : nil
    @lon = domelement["data-longitude"] ? domelement["data-longitude"].to_f : nil
    @body = nil
    @created = nil
    @updated = nil
    @images = []
    @email = nil
    
    # Get the contents of the posting.
    getpostingpage(scanner) do |document|
      if document.search('#postingbody').first.nil?
        @active = false
      else
        @active = true
        @body = document.search('#postingbody').first.content

        dates = document.search('.userbody date')
        @created = DateTime.parse(dates.first.content)
        @updated = DateTime.parse(dates.last.content)

        imagelinks = document.search('#thumbs > a')
        if imagelinks.length != 0
          imagelinks.each { |imagelink| @images.push(imagelink.attr('href')) }
        end

        @email = document.search('a[href^=mailto]').length == 1 ? document.search('a[href^=mailto]').attr('href') : nil
      end
    end
    
    # TODO: Parse emails and/or phone numbers out of the posting.

    # Store car-specific properties on a Car object
    @car = Car.new(self)
  end

  def getpostingpage(scanner)
    # yield Nokogiri::HTML(Net::HTTP.get(@link))
    scanner.pool.schedule do
      puts "#{@link} started by thread #{Thread.current[:id]}"
      result = Nokogiri::HTML(Net::HTTP.get(@link), nil, "UTF-8")
      puts "#{@link} finished by thread #{Thread.current[:id]}"
      yield result
    end
  end

  def to_s
    self.to_json
  end
  
  def to_json(ignore)
    hash = {}
    self.instance_variables.each do |key|
      hash[key.to_s[1..-1]] = self.instance_variable_get(key).class.to_s == "DateTime" ? self.instance_variable_get(key).rfc2822 : self.instance_variable_get(key)
    end
    hash.to_json
  end

end