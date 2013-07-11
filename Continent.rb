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
