# frozen_string_literal: true

require_relative "lib/crawlora/version"

Gem::Specification.new do |spec|
  spec.name = "crawlora"
  spec.version = Crawlora::VERSION
  spec.authors = ["Crawlora"]
  spec.summary = "Ruby SDK for the public Crawlora API."
  spec.description = "Typed, batteries-included Ruby client for the Crawlora web-scraping API: " \
                     "grouped and dynamic operation calls, retries, pagination, hooks, and rate limiting."
  spec.homepage = "https://github.com/Crawlora-org/crawlora-ruby-sdk"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => spec.homepage,
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
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
