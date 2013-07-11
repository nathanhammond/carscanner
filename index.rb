require 'date'
require 'json'
require 'net/http'
require 'nokogiri'
require './ThreadPool'
require './Continent'
require './Region'
require './Listing'
require './Car'
require './CLScanner'

def haversine(lat1, long1, lat2, long2)
  dtor = Math::PI/180
  r = 3959
 
  rlat1 = lat1 * dtor
  rlong1 = long1 * dtor
  rlat2 = lat2 * dtor
  rlong2 = long2 * dtor
 
  dlon = rlong1 - rlong2
  dlat = rlat1 - rlat2
 
  a = Math::sin(dlat/2)**2 + Math::cos(rlat1) * Math::cos(rlat2) * Math::sin(dlon/2)**2
  c = 2 * Math::atan2(Math::sqrt(a), Math::sqrt(1-a))
  d = r * c
 
  return d
end

scanner = CLScanner.new 35.23308, -80.805521
scanner.search("TDI", ["albany", "charlotte"], ["US"])
puts scanner