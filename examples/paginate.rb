# frozen_string_literal: true

# Iterate pages until the API returns an empty page. Run with:
#   CRAWLORA_API_KEY=... ruby examples/paginate.rb
require "crawlora"

Crawlora.client do |client|
  client.paginate_items("airbnb-room-reviews", { id: "YOUR_ROOM_ID" }, max_pages: 3).each do |review|
    puts review.inspect
  end
end
