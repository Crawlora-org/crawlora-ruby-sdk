# Changelog

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
