# frozen_string_literal: true

require_relative "lib/crawlora/version"

Gem::Specification.new do |spec|
  spec.name = "crawlora"
  spec.version = Crawlora::VERSION
  spec.authors = ["Crawlora"]
  spec.email = ["support@crawlora.net"]
  spec.summary = "Official Ruby SDK for the Crawlora web-scraping API"
  spec.description = <<~DESC.gsub("\n", " ").strip
    Crawlora is a web-scraping API for structured public web data — search,
    marketplace, social, finance, media, reviews, and geodata — without running
    your own scrapers. This gem is the official, typed, batteries-included Ruby
    client: grouped helpers (client.bing.search) and dynamic operation calls for
    every endpoint, API-key and JWT auth, automatic retries with exponential
    backoff and Retry-After, numeric and cursor pagination, before/after
    middleware hooks, and client-side rate limiting.
  DESC
  spec.homepage = "https://crawlora.net/"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"

  repo = "https://github.com/Crawlora-org/crawlora-ruby-sdk"
  spec.metadata = {
    "homepage_uri" => "https://crawlora.net/",
    "source_code_uri" => repo,
    "documentation_uri" => "https://crawlora.net/docs",
    "changelog_uri" => "#{repo}/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "#{repo}/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir[
    "lib/**/*.rb",
    "sig/**/*.rbs",
    "docs/**/*.md",
    "examples/**/*.rb",
    "openapi/public.json",
    "README.md",
    "CHANGELOG.md",
    "LICENSE"
  ]
  spec.require_paths = ["lib"]
end
