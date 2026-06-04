# frozen_string_literal: true

# Fetch a transcript in plain-text response mode. Run with:
#   CRAWLORA_API_KEY=... ruby examples/youtube_transcript.rb
require "crawlora"

Crawlora.client do |client|
  transcript = client.request("youtube-transcript", { id: "dQw4w9WgXcQ" }, response_type: "text")
  puts transcript
end
