require 'date'
require 'net/http'
require 'nokogiri'
require 'json'

# Some things we'll be storing information in.
regions = {}
listings = []
searchquery = "TDI"

# Parse the US regions out of craigslist's region list.
results =  Nokogiri::HTML(Net::HTTP.get(URI('http://www.craigslist.org/about/sites'))).search("a[name=US]").first().parent().next_element().search('a')

# Build a usable representation.
results.each { |result|
  hostname = result.attr('href').gsub('http://','').gsub('.craigslist.org','')
  regions[hostname] = { name: result.content, state: result.parent().parent().previous_element().content }
}

# Merge that information with craigslist's geographic information.
areas = JSON.parse(Net::HTTP.get(URI('http://www.craigslist.org/about/areas.json')))
areas.each { |area|
  if regions[area["hostname"]]
    regions[area["hostname"]][:stateabbrev] = area["region"]
    regions[area["hostname"]][:latitude] = area["lat"]
    regions[area["hostname"]][:longitude] = area["lon"]
  end
}
# BAM! Full information regarding US regions.

# Perform a search in a particular region.
def processregion(regionhostname, searchquery)
  # In case there are multiple pages of results from a search
  pages = []
  pagecount = false

  # An accumulator for storing what we need to return.
  result = []

  # Make requests for every page.
  while (pages.length != pagecount)
    # End up with a start of "0" on the first time, 100 is craigslist's page length.
    page = pages.length * 100    

    # Here is the URL we'll be making the request of.
    url = URI("http://#{regionhostname}.craigslist.org/search/cto?query=#{searchquery}&srchType=T&s=#{page}")

    # Get the response and parse it.
    pages << Nokogiri::HTML(Net::HTTP.get(url))

    # If this is the first time through
    if (pagecount == false)

      #check to make sure there are results.
      if pages.last().search('.resulttotal').length() != 0
        # There are results, and we need to see if additional requests are necessary.
        pagecount = (pages.last().search('.resulttotal').first().content().gsub(/[^0-9]/,'').to_i / 100.0).ceil
      else
        # There are no results, we're done here.
        return []
      end
    end
  end

  # Go through each of the pages of results and process the listings
  pages.each { |page|
    # Go through all of the listings on each page
    page.search('.row').each { |listing|
      # Skip listings from other regions in case there are any ("FEW LOCAL RESULTS FOUND").
      if listing.search('a[href^=http]').length() != 0
        next
      end

      # Parse information out of the listing.
      car = {}
      car["id"] = listing["data-pid"]
      car["date"] = listing.search(".date").length() == 1 ? Date.parse(listing.search(".date").first().content) : nil
      # When Craigslist wraps at the end of the year it doesn't add a year field.
      # Fortunately Craigslist has an approximately one month time limit that makes it easy to know which year is being referred to.
      # Overshooting by incrementing the month to make sure that timezone differences between this and CL servers don't result in weirdness
      if car["date"].month > Date.today.month + 1
        car["date"] = car["date"].prev_year
      end
      car["link"] = "http://#{regionhostname}.craigslist.org/cto/#{car['id']}.html"
      car["description"] = listing.search(".pl > a").length() == 1 ? listing.search(".pl > a").first().content : nil
      car["price"] = listing.search("span.price").length() == 1 ? listing.search("span.price").first().content : nil
      car["location"] = listing.search(".l2 small").length() == 1 ? listing.search(".l2 small").first().content.gsub(/[\(\)]/,'').strip : nil
      car["longitude"] = listing["data-longitude"]
      car["latitude"] = listing["data-latitude"]

      # Pull car model year from description
      # Can be wrong, but likely to be accurate.
      if /(?:\b19[0-9]{2}\b|\b20[0-9]{2}\b|\b[0-9]{2}\b)/.match(car["description"]) { |result|

        # Two digit year
        if result[0].length == 2
          # Not an arbitrary wrapping point like it is in MySQL, etc.
          # Cars have known manufacture dates and can't be too far in the future.
          if result[0].to_i <= Date.today.strftime("%y").to_i + 1
            car["year"] = "20#{result[0]}"
          else
            car["year"] = "19#{result[0]}"
          end
        # Four digit year is easy.
        elsif result[0].length == 4
          car["year"] = result[0]
        end
      }
      else
        car["year"] = nil
      end
      
      # This stuff needs to be set by user input.
      car["mileage"] = nil
      # car["features"] = {
      #   "automatic": false,
      #   "sunroof": false,
      #   "navigation": false,
      #   "other": ""
      # }
      
      # Store the region lookup key.
      car["regionhostname"] = regionhostname

      result << car
    }
  }

  return result
end

# Divide the requests across threads.
# But not too few or too many threads for optimization.
iterations = 5
count = (regions.length/iterations.to_f).ceil
(0..(iterations-1)).each { |iteration|
  threads = []
  # Split the requests by region.
  regions.keys.slice(iteration*count,count).each { |regionhostname|
    threads << Thread.new(regionhostname) { |activeregionhostname|
      # Store the response in an accumulator, of sorts.
      listings << processregion(activeregionhostname, searchquery)
    }
  }
  # Don't exit until all threads are complete.
  threads.each { |thread| thread.join }
}

# From processregion we return an array, which means we need to flatten(1) to pull everything up to the top level.
listings = listings.flatten(1)

# Sort all listings by date, descending.
listings.sort! { |a,b|
  if a["date"] == b["date"]
    b["id"].to_i <=> a["id"].to_i
  else
    b["date"] <=> a["date"]
  end
}

# Print the results.
# puts regions.to_json
puts listings.to_json

# time ruby index.rb
# real  0m18.018s
# user  0m13.472s
# sys 0m0.661s