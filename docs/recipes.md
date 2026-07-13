# Crawlora Ruby SDK recipes

Common patterns beyond the README. See [`operations.md`](operations.md) for the
full list of operations.

## Authentication

```ruby
# API key (most endpoints):
Crawlora.client(api_key: "live_…")

# JWT (dashboard/user endpoints). A raw token is sent as "Token <jwt>";
# pass "Bearer <jwt>" yourself to override the scheme.
Crawlora.client(jwt_token: "eyJ…")
```

Both fall back to environment variables: `CRAWLORA_API_KEY` and
`CRAWLORA_BASE_URL`.

## Reddit and Brand

Newer platforms are grouped like every other endpoint:

```ruby
posts = client.reddit.search(q: "ruby", subreddit: "programming")
brand = client.brand.retrieve(domain: "stripe.com")
```

## Software, Reviews, And Market Datasets

```ruby
extensions = client.datasets.chrome_extensions_search(q: "productivity", min_users: 10_000)
cities = client.datasets.numbeo_cities_search(country: "Portugal", sort: "quality_of_life_desc")
software = client.capterra.search(q: "project management")
games = client.metacritic.browse(type: "game", sort: "score")
```

## Airbnb Host Profiles

Look up a public Airbnb host, then page through their listings and guest reviews.

```ruby
host = client.airbnb.host(id: "65056940")
listings = client.airbnb.host_listings(id: "65056940", page: 1)
reviews = client.airbnb.host_reviews(id: "65056940", page: 1)
```

## TrustMRR Verified Startup Revenues

Browse verified startup revenues and the acquisition marketplace on TrustMRR: the marketplace snapshot, the revenue leaderboard, startup detail, and categories.

```ruby
deals = client.trust_mrr.trustmrr_marketplace
board = client.trust_mrr.trustmrr_leaderboard(metric: "mrr")
startup = client.trust_mrr.trustmrr_startup(slug: "stan")
cats = client.trust_mrr.trustmrr_categories
saas = client.trust_mrr.trustmrr_category(slug: "saas")
```

## Retries and Retry-After

```ruby
Crawlora.client(
  retries: 3,
  retry_delay: 0.5,                 # exponential backoff with jitter
  max_retry_delay: 10,
  retry_statuses: [429, 503],       # override the default retryable set
  on_retry: ->(attempt, error, delay) { warn "retry #{attempt} after #{delay}s (#{error.status})" }
)
```

A custom predicate wins over the status set:

```ruby
Crawlora.client(retries: 2, retry_predicate: ->(status, _error) { status == 429 })
```

`Retry-After` (seconds or HTTP-date) is always honored, capped at
`max_retry_delay`.

## Hooks

```ruby
client = Crawlora.client(
  before_request: ->(ctx) { ctx[:headers]["X-Trace-Id"] = SecureRandom.uuid },
  after_response: ->(operation_id, status, _headers, body) {
    body.is_a?(Hash) ? body.merge("_op" => operation_id, "_status" => status) : body
  }
)
```

`before_request` receives a mutable context (`:operation`, `:method`, `:url`,
`:headers`); editing `:url`/`:headers` rewrites the outgoing request.
`after_response` may return a replacement body (return `nil` to keep it).

## Rate limiting and concurrency

```ruby
client = Crawlora.client(rate_limit: 10, max_concurrency: 4)

threads = queries.map do |q|
  Thread.new { client.bing.search(q: q) } # throttled to 10 rps / 4 in-flight
end
threads.each(&:join)
```

## Response modes

```ruby
client.request("youtube-transcript", { id: "abc" }, response_type: "text")   # String
io = client.request("bing-search", { q: "x" }, response_type: "stream")       # StringIO
io.read
```

`auto` (default) parses JSON when the response is JSON and returns text
otherwise.

## Custom transport (testing)

Inject any object responding to
`call(method:, url:, headers:, body:, timeout:)` and returning a
`Crawlora::Response`:

```ruby
fake = ->(**) { Crawlora::Response.new(200, { "content-type" => "application/json" }, '{"data":[]}') }
client = Crawlora.client(transport: fake)
```
