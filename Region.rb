class Region
  attr_accessor :continent

  def initialize(json)
    json.each do |key,value|
      if ["name","hostname","region","country","lat","lon"].include? key
        instance_variable_set("@#{key}", value)
      end
    end
  end

  def reup(continent, regionname)
    @continent = continent
    @regionname = regionname
  end

  def id
    @hostname
  end
  
  def to_s
    self.to_json
  end
  
  def to_json(ignore)
    hash = {}
    self.instance_variables.each do |key|
      # next if ["@id","@postingid"].include? key.to_s
      hash[key.to_s[1..-1]] = self.instance_variable_get key
    end
    hash.to_json
  end

end