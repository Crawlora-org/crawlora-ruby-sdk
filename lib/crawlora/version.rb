# frozen_string_literal: true

module Crawlora
  # SDK release version. Uses the RubyGems prerelease form of the shared
  # `MAJOR.MINOR.PATCH-sdk.N` release tag (the trailing letter segment marks it
  # as a prerelease). Bumped across all SDK repos by the API repo's
  # tools/sdkgen/bump_version.py.
  VERSION = "1.5.0.dev1"
end
