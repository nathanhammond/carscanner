# Why?
require 'rubygems'
require 'bundler/setup'

# New Toys
require 'sinatra'
require 'nokogiri'

# Standard lib
require 'uri'
require 'json'
require 'date'
require 'net/http'

# App specific
require './ThreadPool'
require './Continent'
require './Region'
require './Car'
require './Posting'
require './CLScanner'

scanner = CLScanner.new

get '/' do
  # Store some information about the request
  send_file 'index.html'
end

get '/regions' do
  scanner.regions
end

get '/populate' do
  query = params["q"] ? params["q"] : nil
  regions = params["r"] ? params["r"].split(',') : nil
  continents = params["c"] ? params["c"].split(',') : nil

  scanner.populate(URI.escape(query), regions, continents)
  "success"
end

get '/filter' do
  query = params["q"] ? params["q"] : nil
  regions = params["r"] ? params["r"].split(',') : nil
  continents = params["c"] ? params["c"].split(',') : nil

  # scanner.filter(URI.escape(query), regions, continents)
  scanner.filter
  
end
