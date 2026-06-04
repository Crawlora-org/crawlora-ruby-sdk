# frozen_string_literal: true

module Crawlora
  # SDK release version, in the shared `MAJOR.MINOR.PATCH-sdk.N` tag form (same
  # as the Go/Java/PHP SDKs). RubyGems treats it as a prerelease and normalizes
  # the published gem version to `1.5.0.pre.sdk.2`. Bumped across all SDK repos
  # by the API repo's tools/sdkgen/bump_version.py.
  VERSION = "1.5.0-sdk.2"
end
