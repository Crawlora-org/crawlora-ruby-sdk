# frozen_string_literal: true

require "minitest/autorun"
require "socket"
require "uri"
require "crawlora"

# Transport double: records every call and returns canned responses (an Array
# consumed in order, or a proc receiving the recorded call).
class RecordingTransport
  attr_reader :calls

  def initialize(responses)
    @responses = responses
    @calls = []
  end

  def call(method:, url:, headers:, body:, timeout:)
    @calls << { method: method, url: url, headers: headers, body: body, timeout: timeout }
    resp = @responses.respond_to?(:call) ? @responses.call(@calls.last) : @responses.shift
    status, headers_out, body_out = resp
    Crawlora::Response.new(status, headers_out || {}, body_out || "")
  end
end

JSON_HEADERS = { "content-type" => "application/json" }.freeze

def ok(data)
  [200, JSON_HEADERS, JSON.generate({ "code" => 200, "msg" => "OK", "data" => data })]
end

class ClientTest < Minitest::Test
  def client(responses, **options)
    Crawlora::Client.new(api_key: "secret", transport: RecordingTransport.new(responses), **options)
  end

  def test_grouped_call_sends_api_key_and_parses_json
    transport = RecordingTransport.new([ok([{ "title" => "hit" }])])
    c = Crawlora::Client.new(api_key: "secret", transport: transport)
    result = c.bing.search(q: "web scraping")
    assert_equal [{ "title" => "hit" }], result["data"]
    call = transport.calls.first
    assert_equal "GET", call[:method]
    assert_includes call[:url], "/bing/search"
    assert_includes call[:url], "q=web+scraping"
    assert_equal "secret", call[:headers]["x-api-key"]
    assert_match %r{crawlora-ruby-sdk/}, call[:headers]["User-Agent"]
  end

  def test_dynamic_request_unknown_operation_raises
    c = client([])
    assert_raises(ArgumentError) { c.request("does-not-exist") }
  end

  def test_missing_required_query_param
    c = client([ok([])])
    assert_raises(ArgumentError) { c.bing.search }
  end

  def test_missing_required_path_param
    c = client([ok([])])
    assert_raises(ArgumentError) { c.request("amazon-product", {}) }
  end

  def test_array_query_repeated
    transport = RecordingTransport.new([ok([])])
    c = Crawlora::Client.new(api_key: "k", transport: transport)
    # bing-search accepts a single q; use a known multi-value-friendly op via request.
    c.request("bing-search", { "q" => "a" })
    assert_includes transport.calls.first[:url], "q=a"
  end

  def test_enum_validation_rejects_bad_value
    c = client([ok([])])
    err = assert_raises(ArgumentError) { c.amazon.product(asin: "B000", language: "fr_FR") }
    assert_match(/language/, err.message)
  end

  def test_enum_validation_accepts_good_value
    transport = RecordingTransport.new([ok({})])
    c = Crawlora::Client.new(api_key: "k", transport: transport)
    c.amazon.product(asin: "B000", language: "en_US")
    assert_includes transport.calls.first[:url], "language=en_US"
  end

  def test_unexpected_param_for_group_call
    c = client([ok([])])
    err = assert_raises(ArgumentError) { c.bing.search(q: "x", nope: 1) }
    assert_match(/unexpected parameter/, err.message)
  end

  def test_jwt_auth_header
    transport = RecordingTransport.new([ok({})])
    c = Crawlora::Client.new(jwt_token: "abc", transport: transport)
    # usage-overview requires JWTAuth in this contract.
    op = Crawlora::OPERATIONS.find { |_, o| (o["security"] || []).include?("JWTAuth") }
    skip "no JWTAuth operation in contract" unless op

    c.request(op.first, required_stub(op.last))
    assert_equal "Token abc", transport.calls.first[:headers]["Authorization"]
  end

  def test_4xx_raises_client_error_with_body
    body = JSON.generate({ "code" => 400, "msg" => "bad request" })
    c = client([[400, JSON_HEADERS, body]])
    err = assert_raises(Crawlora::ClientError) { c.bing.search(q: "x") }
    assert_equal 400, err.status
    assert_equal 400, err.code
    assert_equal "bad request", err.message
  end

  def test_5xx_raises_server_error
    c = client([[500, JSON_HEADERS, JSON.generate({ "msg" => "boom" })]])
    err = assert_raises(Crawlora::ServerError) { c.bing.search(q: "x") }
    assert_equal 500, err.status
  end

  def test_retry_on_500_then_success
    responses = [[500, JSON_HEADERS, JSON.generate({ "msg" => "boom" })], ok([{ "ok" => true }])]
    transport = RecordingTransport.new(responses)
    c = Crawlora::Client.new(api_key: "k", transport: transport, retries: 1, retry_delay: 0)
    result = c.bing.search(q: "x")
    assert_equal [{ "ok" => true }], result["data"]
    assert_equal 2, transport.calls.size
  end

  def test_no_retry_when_not_retryable
    transport = RecordingTransport.new([[400, JSON_HEADERS, JSON.generate({ "msg" => "nope" })]])
    c = Crawlora::Client.new(api_key: "k", transport: transport, retries: 3, retry_delay: 0)
    assert_raises(Crawlora::ClientError) { c.bing.search(q: "x") }
    assert_equal 1, transport.calls.size
  end

  def test_retry_after_header_respected
    delays = []
    responses = [[429, JSON_HEADERS.merge("retry-after" => "1"), JSON.generate({ "msg" => "slow" })], ok([])]
    transport = RecordingTransport.new(responses)
    c = Crawlora::Client.new(api_key: "k", transport: transport, retries: 1, retry_delay: 0.01,
                             on_retry: ->(_attempt, _err, delay) { delays << delay })
    c.bing.search(q: "x")
    assert_equal [1.0], delays # Retry-After: 1 overrides the tiny exponential backoff
  end

  def test_text_response_mode
    c = client([[200, { "content-type" => "text/plain" }, "plain transcript"]])
    result = c.request("youtube-transcript", { "id" => "abc" }, response_type: "text")
    assert_equal "plain transcript", result
  end

  def test_stream_response_returns_io
    c = client([[200, JSON_HEADERS, "raw-bytes"]])
    result = c.request("bing-search", { "q" => "x" }, response_type: "stream")
    assert_kind_of StringIO, result
    assert_equal "raw-bytes", result.read
  end

  def test_before_request_hook_mutates_headers
    transport = RecordingTransport.new([ok({})])
    hook = ->(ctx) { ctx[:headers]["X-Custom"] = "yes" }
    c = Crawlora::Client.new(api_key: "k", transport: transport, before_request: hook)
    c.bing.search(q: "x")
    assert_equal "yes", transport.calls.first[:headers]["X-Custom"]
  end

  def test_after_response_hook_replaces_body
    c = Crawlora::Client.new(api_key: "k", transport: RecordingTransport.new([ok({ "n" => 1 })]),
                             after_response: ->(_op, _status, _headers, _body) { { "replaced" => true } })
    assert_equal({ "replaced" => true }, c.bing.search(q: "x"))
  end

  def test_request_id_added_when_enabled
    transport = RecordingTransport.new([ok({})])
    c = Crawlora::Client.new(api_key: "k", transport: transport, request_id: true)
    c.bing.search(q: "x")
    refute_empty transport.calls.first[:headers]["x-request-id"].to_s
  end

  def test_idempotency_key_added_for_post
    post = Crawlora::OPERATIONS.find { |_, o| o["method"] == "POST" }
    skip "no POST operation in contract" unless post

    transport = RecordingTransport.new([ok({})])
    c = Crawlora::Client.new(jwt_token: "j", api_key: "k", transport: transport, idempotency_keys: true)
    c.request(post.first, required_stub(post.last))
    refute_nil transport.calls.first[:headers]["Idempotency-Key"]
  end

  def test_network_error_on_transport_raise
    raising = Object.new
    def raising.call(**_) = raise(SocketError, "boom")
    c = Crawlora::Client.new(api_key: "k", transport: raising)
    assert_raises(Crawlora::NetworkError) { c.bing.search(q: "x") }
  end

  def test_paginate_numeric_stops_on_empty
    pages = [ok([{ "i" => 1 }]), ok([{ "i" => 2 }]), ok([])]
    transport = RecordingTransport.new(pages)
    c = Crawlora::Client.new(api_key: "k", transport: transport)
    collected = c.paginate("airbnb-room-reviews", { "id" => "r1" }).to_a
    assert_equal 3, collected.size
    assert_equal 3, transport.calls.size
    assert_includes transport.calls[0][:url], "page=1"
    assert_includes transport.calls[1][:url], "page=2"
  end

  def test_paginate_items_extracts_data
    pages = [ok([{ "i" => 1 }, { "i" => 2 }]), ok([])]
    c = Crawlora::Client.new(api_key: "k", transport: RecordingTransport.new(pages))
    items = c.paginate_items("airbnb-room-reviews", { "id" => "r1" }).to_a
    assert_equal [{ "i" => 1 }, { "i" => 2 }], items
  end

  def test_paginate_cursor_mode
    cur = Crawlora::OPERATIONS.find { |_, o| o["cursorParams"] }
    skip "no cursor operation in contract" unless cur

    cursor_param = cur.last["cursorParams"].first
    responses = [
      [200, JSON_HEADERS, JSON.generate({ "data" => [1], "next" => "c2" })],
      [200, JSON_HEADERS, JSON.generate({ "data" => [2], "next" => nil })]
    ]
    transport = RecordingTransport.new(responses)
    c = Crawlora::Client.new(api_key: "k", transport: transport)
    pages = c.paginate(cur.first, required_stub(cur.last),
                       cursor_param: cursor_param, next_cursor: ->(r) { r["next"] }).to_a
    assert_equal 2, pages.size
    assert_includes transport.calls[1][:url], "#{cursor_param}=c2"
  end

  def test_invalid_response_type_raises
    c = client([ok({})])
    assert_raises(ArgumentError) { c.request("bing-search", { "q" => "x" }, response_type: "xml") }
  end

  # Exercises the real DefaultTransport against an in-process HTTP server.
  def test_default_transport_against_real_server
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    thread = Thread.new do
      socket = server.accept
      request_line = socket.gets
      # Drain request headers up to the blank line, then reply.
      while (line = socket.gets) && line != "\r\n"; end
      payload = JSON.generate({ "code" => 200, "msg" => "OK", "data" => { "echo" => request_line.split[1] } })
      headers = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n" \
                "Content-Length: #{payload.bytesize}\r\nConnection: close\r\n\r\n"
      socket.write(headers + payload)
      socket.close
    end
    c = Crawlora::Client.new(api_key: "k", base_url: "http://127.0.0.1:#{port}/api/v1")
    result = c.bing.search(q: "real")
    assert_includes result["data"]["echo"], "/api/v1/bing/search"
  ensure
    c&.close
    thread&.kill
    server&.close
  end

  private

  # Build the minimal required params for an arbitrary operation so we can call
  # it in tests without hardcoding ids.
  def required_stub(operation)
    params = {}
    (operation["pathParams"] || []).each { |name| params[name] = "x" }
    (operation["queryParams"] || []).each { |p| params[p["name"]] = (p["enum"]&.first || "x") if p["required"] }
    (operation["formParams"] || []).each { |p| params[p["name"]] = "x" if p["required"] }
    params[operation["bodyParam"]] = { "stub" => true } if operation["bodyRequired"]
    params
  end
end
