class Car
  attr_reader :year

  def initialize(posting)
    @id = nil
    @postingid = posting.id
    @year = findyear(posting.description)
    
    # TODO: condition, mileage, features, color(s)...
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