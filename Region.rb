class Region
  attr_accessor :continent
  attr_reader :distance

  def initialize(scanner, json)
    json.each do |key,value|
      if ["name","hostname","region","country","lat","lon"].include? key
        instance_variable_set("@#{key}", value)
      end
    end

    @distance = haversine(scanner.lat, scanner.lon, @lat, @lon)
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