require 'date'
require 'net/http'
require 'nokogiri'
require 'json'

regions = {}
listings = []
searchquery = "TDI"

# Get the US regions from craigslist.
results =  Nokogiri::HTML(Net::HTTP.get(URI('http://www.craigslist.org/about/sites'))).search("a[name=US]").first().parent().next_element().search('a')

# Build a usable representation.
results.each { |result|
  hostname = result.attr('href').gsub('http://','').gsub('.craigslist.org','')
  regions[hostname] = { name: result.content, state: result.parent().parent().previous_element().content }
}

# merge that information with craigslist's geographic information.
areas = JSON.parse(Net::HTTP.get(URI('http://www.craigslist.org/about/areas.json')))
areas.each { |area|
  if regions[area["hostname"]]
    regions[area["hostname"]][:stateabbrev] = area["region"]
    regions[area["hostname"]][:latitude] = area["lat"]
    regions[area["hostname"]][:longitude] = area["lon"]
  end
}
# BAM! Full information regarding US regions.

# Perform the search in each region.
def processregion(regionhostname, searchquery)
  pages = []
  pagecount = false
  result = []

  while (pages.length != pagecount)
    page = pages.length * 100    
    url = URI("http://#{regionhostname}.craigslist.org/search/cto?query=#{searchquery}&srchType=T&s=#{page}")
    pages << Nokogiri::HTML(Net::HTTP.get(url))

    # if this is the first time through
    if (pagecount == false)
      if pages.last().search('.resulttotal').length() != 0
        # There are results
        pagecount = (pages.last().search('.resulttotal').first().content().gsub(/[^0-9]/,'').to_i / 100.0).ceil
      else
        # There are no results, we're done here.
        return []
      end
    end
  end

  # Go through the pages and process the listings
  pages.each { |page|
    page.search('.row').each { |listing|
      # Skip listings from other regions.
      if listing.search('a[href^=http]').length() != 0
        next
      end
      car = {}
      car["id"] = listing["data-pid"]
      car["date"] = listing.search(".date").length() == 1 ? Date.parse(listing.search(".date").first().content) : nil
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
      if /(?:\b19[0-9]{2}\b|\b20[0-9]{2}\b|\b[0-9]{2}\b)/.match(car["description"]) { |result|

        if result[0].length == 2
          if result[0].to_i <= Date.today.strftime("%y").to_i + 1
            car["year"] = "20#{result[0]}"
          else
            car["year"] = "19#{result[0]}"
          end
        elsif result[0].length == 4
          car["year"] = result[0]
        end
      }
      else
        car["year"] = nil
      end
      
      car["mileage"] = nil
      car["features"]
      
      car["regionhostname"] = regionhostname

      result << car
    }
  }

  return result
end

# Make the requests in threads.
iterations = 5
count = (regions.length/iterations.to_f).ceil
(0..(iterations-1)).each { |iteration|
  threads = []
  regions.keys.slice(iteration*count,count).each { |regionhostname|
    threads << Thread.new(regionhostname) { |activeregionhostname|
      listings << processregion(activeregionhostname, searchquery)
    }
  }
  threads.each { |thread| thread.join }
}

listings = listings.flatten(1)
listings.sort! { |a,b|
  if a["date"] == b["date"]
    b["id"].to_i <=> a["id"].to_i
  else
    b["date"] <=> a["date"]
  end
}

# Collate those searches for presentment.
# puts regions.to_json
puts listings.to_json