# frozen_string_literal: true

require_relative "crawlora/version"
require_relative "crawlora/errors"
require_relative "crawlora/pagination"
require_relative "crawlora/operations"
require_relative "crawlora/client"

# Ruby SDK for the public Crawlora API.
#
# Quick start:
#
#   require "crawlora"
#
#   client = Crawlora.client(api_key: ENV["CRAWLORA_API_KEY"])
#   result = client.bing.search(q: "web scraping")
#   puts result["data"]
module Crawlora
  # Build a Client. When a block is given, the client is yielded and closed
  # afterwards (releasing pooled connections).
  def self.client(**options)
    client = Client.new(**options)
    return client unless block_given?

    begin
      yield client
    ensure
      client.close
    end
  end
end
