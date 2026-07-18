# frozen_string_literal: true

module Crawlora
  # SDK release version, in the shared `MAJOR.MINOR.PATCH-sdk.N` tag form (same
  # as the Go/Java/PHP SDKs). RubyGems treats it as a prerelease and normalizes
  # the published gem version (the `-` becomes `.pre.`, e.g. `1.5.0.pre.sdk.N`).
  # Bumped across all SDK repos by the API repo's tools/sdkgen/bump_version.py.
  VERSION = "1.20.0-sdk.1"
end
