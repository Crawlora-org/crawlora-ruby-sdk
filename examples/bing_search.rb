# frozen_string_literal: true

# Basic search call. Run with:
#   CRAWLORA_API_KEY=... ruby examples/bing_search.rb
require "crawlora"

Crawlora.client do |client|
  result = client.bing.search(q: "web scraping")
  result["data"].each { |item| puts item["title"] || item.inspect }
end
