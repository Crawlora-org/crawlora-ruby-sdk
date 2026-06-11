# Changelog

## v1.8.0-sdk.1

- Added two new platforms, regenerated from the public API contract (now 499
  operations): **Redfin** (real-estate `search`, `property`, `estimate`,
  `region-trends`, `similar`) and **Web** (generic `web-scrape`, `contact`, and
  the `antibot-check` diagnostic).
- Refreshed response schemas: `contact` gains `crawl_status`, `web-scrape` gains
  `cache_state`/`cached_at`/`max_age`, and the Spotify country-hub responses gain
  `partialErrors`.

## v1.7.0-sdk.1

- Added six new platforms, regenerated from the public API contract (now 491
  operations): **Polymarket**, **Kalshi**, and **Metaculus** (prediction
  markets); **IMDb**, **Rotten Tomatoes**, and **Box Office Mojo** (film/TV).
- Expanded **Reddit**: subreddit about/comments, multi-subreddit posts,
  domain posts, user posts/comments, and trends.

## 1.6.0-sdk.1

- Added the **Reddit** platform (`reddit.search`, `reddit.post`,
  `reddit.comments`, `reddit.subreddit_posts`) and the **Brand** platform
  (`brand.retrieve`), plus Yahoo Finance `yahoo_finance.lookup`. Regenerated from
  the public API contract.

## 1.5.0-sdk.3

- Richer RBS: generated `sig/crawlora.rbs` now declares typed keyword parameters
  per operation (Steep/Sorbet users get real signatures instead of `**untyped`).
- Internal cleanups: split the request and pagination methods into focused
  private helpers, enabled tuned rubocop metric budgets, and hardened multipart
  `Content-Disposition` field/filename escaping. No public API changes.

## 1.5.0-sdk.2

- Packaging: point the gem homepage at https://crawlora.net/, expand the gem
  description, and add `documentation_uri` / `source_code_uri` / `bug_tracker_uri`
  metadata for a richer RubyGems listing. No client or API changes.

## 1.5.0-sdk.1

- Initial release of the Crawlora Ruby SDK.
- Grouped helpers (`client.<group>.<method>`) and dynamic `request`/`operation`
  calls for every public operation, generated from the shared OpenAPI contract.
- Configurable retries with exponential backoff, jitter, and `Retry-After`
  support; `on_retry` hook.
- Numeric and cursor pagination (`paginate` / `paginate_items`).
- `before_request` / `after_response` middleware, opt-in `request_id` and
  `idempotency_keys`, client-side `rate_limit` / `max_concurrency`.
- `auto` / `json` / `text` / `stream` response modes.
- Typed error hierarchy: `Crawlora::Error`, `ClientError`, `ServerError`,
  `NetworkError`.
