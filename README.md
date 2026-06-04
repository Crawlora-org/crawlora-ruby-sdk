# Crawlora Ruby SDK

Ruby client for the public [Crawlora](https://crawlora.net) web-scraping API. It
wraps every public endpoint with grouped helpers and a dynamic call interface,
plus retries, pagination, middleware hooks, and client-side rate limiting.

- **Base URL:** `https://api.crawlora.net/api/v1`
- **Auth:** API key (`x-api-key`) or JWT (`Authorization`)
- **Ruby:** 3.0+
- Operation reference: [`docs/operations.md`](docs/operations.md) · recipes: [`docs/recipes.md`](docs/recipes.md)

## Install

```ruby
# Gemfile
gem "crawlora"
```

```sh
gem install crawlora
```

## Quick start

```ruby
require "crawlora"

# Reads CRAWLORA_API_KEY from the environment if api_key: is omitted.
client = Crawlora.client(api_key: ENV["CRAWLORA_API_KEY"])

result = client.bing.search(q: "web scraping")
result["data"].each { |item| puts item["title"] }

client.close # release pooled keep-alive connections
```

Pass a block to auto-close:

```ruby
Crawlora.client do |client|
  puts client.amazon.product(asin: "B07FZ8S74R", language: "en_US")
end
```

## Calling operations

Grouped helpers map directly to the API (`client.<group>.<method>`):

```ruby
client.youtube.video(id: "dQw4w9WgXcQ")
client.google.search(q: "crawlora", country: "US")
```

Or call any operation dynamically by its id — handy for metaprogramming:

```ruby
client.request("bing-search", { q: "web scraping", page: 2 })

# Discover operations:
Crawlora::OPERATION_COUNT            # => total operations
Crawlora::GROUPS["bing"]             # => { "search" => "bing-search", ... }
Crawlora::OperationId::BING_SEARCH   # => "bing-search"
```

## Configuration

```ruby
Crawlora.client(
  api_key: "…",
  timeout: 30,             # seconds per request
  retries: 2,              # retry attempts on retryable failures
  retry_delay: 0.25,       # base backoff (exponential + jitter, honors Retry-After)
  request_id: true,        # attach an x-request-id to every call
  idempotency_keys: true,  # stable Idempotency-Key on POST/PATCH
  rate_limit: 5,           # max requests/second (client-side)
  max_concurrency: 4,      # max in-flight requests across threads
  headers: { "X-Tenant" => "acme" }
)
```

Per-request overrides use the reserved `_`-prefixed keyword on grouped calls, or
keyword args on `request`:

```ruby
client.bing.search(q: "x", _timeout: 5, _headers: { "X-Trace" => "1" })
client.request("bing-search", { q: "x" }, response_type: "text", retries: 0)
```

## Pagination

```ruby
# Numeric (page/offset) — stops on the first empty page:
client.paginate_items("airbnb-room-reviews", { id: "123" }, max_pages: 5).each do |review|
  puts review["text"]
end

# Cursor mode — supply the cursor param and a next-cursor extractor:
client.paginate("producthunt-leaderboard", {},
                cursor_param: "cursor", next_cursor: ->(page) { page["next_cursor"] }) do |page|
  puts page["data"]
end
```

## Error handling

```ruby
begin
  client.bing.search(q: "x")
rescue Crawlora::ClientError => e   # 4xx
  warn "rejected (#{e.status}): #{e.message} #{e.code}"
rescue Crawlora::ServerError => e   # 5xx
  warn "server error: #{e.status}"
rescue Crawlora::NetworkError => e  # timeout / transport failure
  warn "network: #{e.message}"
end
```

All inherit from `Crawlora::Error`, which exposes `status`, `code`, `body`,
`raw_body`, `headers`, and `request_id`.

## License

MIT. See [LICENSE](LICENSE).
