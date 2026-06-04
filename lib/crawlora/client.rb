# frozen_string_literal: true

require "cgi"
require "json"
require "net/http"
require "securerandom"
require "set"
require "stringio"
require "time"
require "uri"

require_relative "errors"
require_relative "pagination"
require_relative "operations"

module Crawlora
  DEFAULT_BASE_URL = "https://api.crawlora.net/api/v1"
  DEFAULT_MAX_RETRY_DELAY = 30.0
  DEFAULT_RETRY_STATUSES = [408, 409, 425, 429].freeze
  RESPONSE_TYPES = %w[auto json text stream].freeze

  Response = Struct.new(:status, :headers, :body)

  # Default keep-alive transport: reuses one Net::HTTP connection per origin so
  # repeated calls share a TCP/TLS session. Inject a callable transport for
  # tests or custom HTTP stacks.
  class DefaultTransport
    def initialize
      @connections = {}
      @mutex = Mutex.new
    end

    def call(method:, url:, headers:, body:, timeout:)
      uri = URI.parse(url)
      http = connection(uri, timeout)
      request = build_request(method, uri, headers, body)
      response = http.request(request)
      Response.new(response.code.to_i, response.to_hash.transform_values { |v| v.is_a?(Array) ? v.join(", ") : v }, response.body || "")
    end

    def close
      @mutex.synchronize do
        @connections.each_value { |http| http.finish if http.started? }
        @connections.clear
      end
    end

    private

    def connection(uri, timeout)
      key = "#{uri.scheme}://#{uri.host}:#{uri.port}"
      @mutex.synchronize do
        http = @connections[key]
        if http.nil?
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == "https"
          http.keep_alive_timeout = 30
          @connections[key] = http
        end
        http.open_timeout = timeout
        http.read_timeout = timeout
        http.start unless http.started?
        http
      end
    end

    def build_request(method, uri, headers, body)
      klass = Net::HTTP.const_get(method.capitalize)
      request = klass.new(uri.request_uri)
      headers.each { |name, value| request[name] = value }
      request.body = body if body
      request
    end
  end

  # Optional client-side throttle: caps concurrency and spaces requests to a
  # maximum rate (requests per second).
  class RateLimiter
    def initialize(rps, concurrency)
      @interval = rps&.positive? ? 1.0 / rps : 0.0
      @slots = concurrency&.positive? ? concurrency : nil
      @available = @slots
      @mutex = Mutex.new
      @cond = ConditionVariable.new
      @next_at = 0.0
    end

    def run
      acquire
      begin
        space
        yield
      ensure
        release
      end
    end

    private

    def acquire
      return if @slots.nil?

      @mutex.synchronize do
        @cond.wait(@mutex) while @available <= 0
        @available -= 1
      end
    end

    def release
      return if @slots.nil?

      @mutex.synchronize do
        @available += 1
        @cond.signal
      end
    end

    def space
      return if @interval.zero?

      wait = 0.0
      @mutex.synchronize do
        now = monotonic
        wait = [0.0, @next_at - now].max
        @next_at = [now, @next_at].max + @interval
      end
      sleep(wait) if wait.positive?
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end

  # Synchronous client for the Crawlora API.
  #
  # Call operations via grouped helpers (+client.bing.search(q: "...")+) or
  # dynamically (+client.request("bing-search", q: "...")+). Supports
  # configurable retries, an +on_retry+ hook, opt-in +request_id+ and
  # +idempotency_keys+, +before_request+/+after_response+ middleware, client-side
  # +rate_limit+/+max_concurrency+, pagination (+paginate+/+paginate_items+), and
  # +response_type: "stream"+. Uses a keep-alive connection pool by default; call
  # +close+ (or use the block form of +Crawlora.client+) to release connections.
  class Client
    attr_reader :api_key, :jwt_token, :base_url, :timeout, :retries, :retry_delay,
                :max_retry_delay, :retry_statuses, :headers, :user_agent

    def initialize(
      api_key: nil, jwt_token: nil, base_url: nil, timeout: 30,
      retries: 0, retry_delay: 0.25, max_retry_delay: DEFAULT_MAX_RETRY_DELAY,
      retry_statuses: nil, retry_predicate: nil, on_retry: nil,
      request_id: false, idempotency_keys: false,
      rate_limit: nil, max_concurrency: nil, logger: nil,
      before_request: nil, after_response: nil,
      headers: nil, user_agent: nil, transport: nil
    )
      # Precedence: explicit argument > environment variable > default.
      @api_key = api_key || ENV.fetch("CRAWLORA_API_KEY", "")
      @jwt_token = jwt_token || ""
      @base_url = (base_url || ENV["CRAWLORA_BASE_URL"] || DEFAULT_BASE_URL).chomp("/")
      @timeout = timeout
      @retries = [0, retries.to_i].max
      @retry_delay = [0.0, retry_delay.to_f].max
      @max_retry_delay = [0.0, max_retry_delay.to_f].max
      @retry_statuses = retry_statuses&.to_a&.to_set
      @retry_predicate = retry_predicate
      @on_retry = on_retry
      @request_id = request_id
      @idempotency_keys = idempotency_keys
      @rate_limiter = rate_limit || max_concurrency ? RateLimiter.new(rate_limit, max_concurrency) : nil
      @logger = logger
      @before_request = as_hook_list(before_request)
      @after_response = as_hook_list(after_response)
      @headers = headers ? headers.dup : {}
      @user_agent = user_agent || "crawlora-ruby-sdk/#{VERSION}"
      @transport = transport || DefaultTransport.new

      @groups = {}
      GROUPS.each do |group_name, operations|
        @groups[group_name] = OperationGroup.new(self, operations)
        define_singleton_method(group_name) { @groups[group_name] }
      end
    end

    # Release pooled keep-alive connections, if the transport supports it.
    def close
      @transport.close if @transport.respond_to?(:close)
    end

    def operation(operation_id, params = {}, **options)
      request(operation_id, params, **options)
    end

    def request(operation_id, params = {}, response_type: "auto", timeout: nil, headers: nil,
                retries: nil, retry_predicate: nil)
      operation = OPERATIONS[operation_id]
      raise ArgumentError, "unknown Crawlora operation: #{operation_id}" if operation.nil?

      response_type = validate_response_type(response_type)
      log(event: "request", operation: operation_id)
      max_retries = retries.nil? ? @retries : [0, retries.to_i].max
      idempotency_key =
        @idempotency_keys && %w[POST PATCH].include?(operation["method"]) ? SecureRandom.hex(16) : nil

      attempt = 0
      loop do
        return send_request(operation, stringify_keys(params), response_type: response_type,
                                                               timeout: timeout, headers: headers, idempotency_key: idempotency_key)
      rescue Error => e
        retryable = retry_predicate ? retry_predicate.call(e.status, e) : retryable?(e.status, e)
        raise if attempt >= max_retries || !retryable

        attempt += 1
        delay = compute_retry_delay(attempt, e.headers)
        log(event: "retry", operation: operation_id, attempt: attempt, status: e.status, delay: delay)
        @on_retry&.call(attempt, e, delay)
        sleep(delay) if delay.positive?
      end
    end

    # Yield successive pages of a paginated operation.
    #
    # Numeric mode (default) advances the +page+/+offset+ query parameter and
    # stops on an empty page. Cursor mode (pass both +cursor_param+ and a
    # +next_cursor+ extractor) sends the cursor parameter and stops when
    # +next_cursor+ returns a falsy value.
    def paginate(operation_id, params = {}, page_param: nil, cursor_param: nil, next_cursor: nil,
                 start: nil, step: 1, max_pages: nil, response_type: "auto", timeout: nil, headers: nil)
      unless block_given?
        return enum_for(:paginate, operation_id, params, page_param: page_param, cursor_param: cursor_param,
                                                         next_cursor: next_cursor, start: start, step: step, max_pages: max_pages,
                                                         response_type: response_type, timeout: timeout, headers: headers)
      end

      operation = OPERATIONS[operation_id]
      raise ArgumentError, "unknown Crawlora operation: #{operation_id}" if operation.nil?

      base_params = stringify_keys(params)

      if cursor_param || next_cursor
        raise ArgumentError, "cursor pagination requires both cursor_param and next_cursor" unless cursor_param && next_cursor

        query_names = (operation["queryParams"] || []).map { |p| p["name"] }
        unless query_names.include?(cursor_param)
          raise ArgumentError, "cursor_param #{cursor_param.inspect} is not a query parameter of operation #{operation_id}"
        end

        cursor = start
        fetched = 0
        while max_pages.nil? || fetched < max_pages
          page_params = base_params.dup
          page_params[cursor_param] = cursor unless cursor.nil?
          response = request(operation_id, page_params, response_type: response_type, timeout: timeout, headers: headers)
          yield response
          fetched += 1
          cursor = next_cursor.call(response)
          break unless cursor && !(cursor.respond_to?(:empty?) && cursor.empty?)
        end
        return
      end

      page_param ||= Pagination.detect_page_param(operation)
      raise ArgumentError, "operation #{operation_id} has no page or offset query parameter to paginate" unless page_param

      page_value = start.nil? ? Pagination.default_start(page_param) : start
      fetched = 0
      while max_pages.nil? || fetched < max_pages
        page_params = base_params.merge(page_param => page_value)
        response = request(operation_id, page_params, response_type: response_type, timeout: timeout, headers: headers)
        yield response
        fetched += 1
        break if Pagination.page_empty?(response)

        page_value += step
      end
    end

    # Yield individual items across pages. +items+ extracts the list from a page
    # (default: the Crawlora +data+ array).
    def paginate_items(operation_id, params = {}, items: nil, **options, &block)
      return enum_for(:paginate_items, operation_id, params, items: items, **options) unless block_given?

      extract = items || Pagination.method(:default_items)
      paginate(operation_id, params, **options) do |page|
        extract.call(page).each(&block)
      end
    end

    private

    def send_request(operation, params, response_type:, timeout:, headers:, idempotency_key: nil)
      url, body, body_headers = build_request(@base_url, operation, params)
      request_headers = merge_headers(
        @headers,
        auth_headers(operation["security"] || [], @api_key, @jwt_token),
        @user_agent.empty? ? {} : { "User-Agent" => @user_agent },
        body_headers,
        headers || {}
      )
      req_id =
        if @request_id
          ensure_request_id(request_headers)
        else
          v = header_value(request_headers, "x-request-id")
          v.empty? ? nil : v
        end
      request_headers["Idempotency-Key"] = idempotency_key if idempotency_key && header_value(request_headers, "idempotency-key").empty?
      unless @before_request.empty?
        ctx = { operation: operation["id"], method: operation["method"], url: url, headers: request_headers }
        @before_request.each { |hook| hook.call(ctx) }
        url = ctx[:url]
        request_headers = ctx[:headers]
      end

      request_timeout = timeout.nil? ? @timeout : timeout
      begin
        response =
          if @rate_limiter
            @rate_limiter.run do
              @transport.call(method: operation["method"], url: url, headers: request_headers, body: body, timeout: request_timeout)
            end
          else
            @transport.call(method: operation["method"], url: url, headers: request_headers, body: body, timeout: request_timeout)
          end
      rescue StandardError => e
        message = timeout_error?(e) ? "Crawlora request timed out" : "Crawlora transport error"
        raise NetworkError.new(message, request_id: req_id, cause: e)
      end

      raw_body = response.body.to_s
      is_error = response.status < 200 || response.status >= 300
      return StringIO.new(response.body.to_s) if response_type == "stream" && !is_error

      parse_mode = response_type == "stream" ? "auto" : response_type
      begin
        parsed = parse_response(response.body.to_s, header_value(response.headers, "content-type"), parse_mode)
      rescue JSON::ParserError => e
        raise Error.new("Crawlora JSON parse error", status: response.status, raw_body: raw_body,
                                                     headers: response.headers, request_id: req_id, cause: e)
      end

      if is_error
        code = parsed.is_a?(Hash) ? parsed["code"] : nil
        message = parsed.is_a?(Hash) && parsed["msg"] && !parsed["msg"].to_s.empty? ? parsed["msg"] : "HTTP #{response.status}"
        raise Crawlora.error_class_for(response.status).new(
          message, status: response.status, code: code, body: parsed,
                   raw_body: raw_body, headers: response.headers, request_id: req_id
        )
      end

      @after_response.each do |hook|
        result = hook.call(operation["id"], response.status, response.headers, parsed)
        parsed = result unless result.nil?
      end
      parsed
    end

    def retryable?(status, exc)
      return @retry_predicate.call(status, exc) ? true : false if @retry_predicate
      return status.zero? || @retry_statuses.include?(status) if @retry_statuses

      status.zero? || DEFAULT_RETRY_STATUSES.include?(status) || status >= 500
    end

    def compute_retry_delay(attempt, headers)
      retry_after = retry_after_delay(headers, @max_retry_delay)
      return retry_after if retry_after
      return 0.0 if @retry_delay <= 0

      delay = @retry_delay * (2**[0, attempt - 1].max)
      delay + (rand * (@retry_delay / 2))
    end

    def log(event)
      @logger&.call(event)
    end

    def as_hook_list(value)
      return [] if value.nil?
      return [value] if value.respond_to?(:call)

      value.to_a
    end

    def stringify_keys(params)
      (params || {}).each_with_object({}) { |(k, v), out| out[k.to_s] = v }
    end

    def build_request(base_url, operation, params)
      validate_required_params(operation, params)
      validate_enum_params(operation, params)

      path = operation["path"].dup
      (operation["pathParams"] || []).each do |name|
        value = params[name]
        raise ArgumentError, "missing required path parameter: #{name}" if value.nil? || value == ""

        path = path.gsub("{#{name}}", url_escape(value))
      end

      query = []
      (operation["queryParams"] || []).each do |parameter|
        name = parameter["name"]
        value = params[name]
        next if value.nil? || value == ""

        if value.is_a?(Array)
          value.each { |item| query << [name, stringify_param(item)] }
        else
          query << [name, stringify_param(value)]
        end
      end
      url = base_url + path
      url += "?#{URI.encode_www_form(query)}" unless query.empty?

      return [url, *multipart_body(operation["formParams"], params)] if operation["formParams"] && !operation["formParams"].empty?

      body_param = operation["bodyParam"]
      if body_param
        value = params.fetch(body_param, params["body"])
        return [url, JSON.generate(value), { "content-type" => "application/json" }] unless value.nil?
      end

      [url, nil, {}]
    end

    def validate_required_params(operation, params)
      (operation["pathParams"] || []).each do |name|
        raise ArgumentError, "missing required path parameter: #{name}" if missing?(params[name])
      end
      %w[queryParams formParams].each do |location|
        (operation[location] || []).each do |parameter|
          next unless parameter["required"] && missing?(params[parameter["name"]])

          raise ArgumentError, "missing required #{parameter["in"] || "request"} parameter: #{parameter["name"]}"
        end
      end
      return unless operation["bodyRequired"]

      body_param = operation["bodyParam"]
      return unless missing?(params[body_param]) && missing?(params["body"])

      raise ArgumentError, "missing required body parameter: #{body_param}"
    end

    def validate_enum_params(operation, params)
      %w[queryParams formParams].each do |location|
        (operation[location] || []).each do |parameter|
          enum_values = parameter["enum"] || []
          value = params[parameter["name"]]
          next if enum_values.empty? || missing?(value)

          values = value.is_a?(Array) ? value : [value]
          values.each do |item|
            next if enum_values.include?(stringify_param(item))

            location_name = parameter["in"] || "request"
            raise ArgumentError, "invalid #{location_name} parameter #{parameter["name"]}: expected one of #{enum_values.join(", ")}"
          end
        end
      end
    end

    def missing?(value)
      value.nil? || value == "" || (value.is_a?(Array) && value.empty?)
    end

    def multipart_body(form_params, params)
      boundary = "crawlora-#{SecureRandom.hex(16)}"
      chunks = +""
      form_params.each do |parameter|
        name = parameter["name"]
        next unless params.key?(name) && !params[name].nil?

        value = params[name]
        chunks << "--#{boundary}\r\n"
        if parameter["type"] == "file"
          filename, data = read_file_value(value)
          chunks << %(Content-Disposition: form-data; name="#{name}"; filename="#{filename}"\r\n)
          chunks << "Content-Type: application/octet-stream\r\n\r\n"
          chunks << data
          chunks << "\r\n"
        else
          chunks << %(Content-Disposition: form-data; name="#{name}"\r\n\r\n#{value}\r\n)
        end
      end
      chunks << "--#{boundary}--\r\n"
      [chunks, { "content-type" => "multipart/form-data; boundary=#{boundary}" }]
    end

    def read_file_value(value)
      return ["upload.bin", value] if value.is_a?(String) && !File.exist?(value)
      return [File.basename(value), File.binread(value)] if value.is_a?(String)
      return [File.basename(value.path), value.read] if value.respond_to?(:read) && value.respond_to?(:path)

      ["upload.bin", value.read]
    end

    def auth_headers(security, api_key, jwt_token)
      headers = {}
      headers["x-api-key"] = api_key if security.include?("ApiKeyAuth") && !api_key.empty?
      if security.include?("JWTAuth") && !jwt_token.empty?
        prefixed = jwt_token.downcase.start_with?("token ", "bearer ")
        headers["Authorization"] = prefixed ? jwt_token : "Token #{jwt_token}"
      end
      headers
    end

    def merge_headers(*sources)
      headers = {}
      names = {}
      sources.each do |source|
        source.each do |name, value|
          lower = name.downcase
          existing = names[lower]
          headers.delete(existing) if existing && existing != name
          headers[name] = value.to_s
          names[lower] = name
        end
      end
      headers
    end

    def validate_response_type(response_type)
      return response_type if RESPONSE_TYPES.include?(response_type)

      raise ArgumentError, "invalid response_type: expected one of #{RESPONSE_TYPES.join(", ")}"
    end

    def parse_response(body, content_type, response_type)
      return body if response_type == "text"

      if response_type == "json" || content_type.downcase.include?("application/json")
        return body.empty? ? nil : JSON.parse(body)
      end

      body
    end

    def stringify_param(value)
      return value ? "true" : "false" if [true, false].include?(value)

      value.to_s
    end

    def url_escape(value)
      CGI.escape(value.to_s).gsub("+", "%20")
    end

    def ensure_request_id(headers)
      existing = header_value(headers, "x-request-id")
      return existing unless existing.empty?

      request_id = SecureRandom.hex(16)
      headers["x-request-id"] = request_id
      request_id
    end

    def retry_after_delay(headers, cap)
      value = header_value(headers, "retry-after")
      return nil if value.empty?

      seconds = Float(value, exception: false)
      return [seconds, cap].min if seconds&.positive?

      begin
        delay = Time.httpdate(value).to_f - Time.now.to_f
      rescue ArgumentError
        return nil
      end
      delay.positive? ? [delay, cap].min : nil
    end

    def header_value(headers, name)
      headers.each { |key, value| return value.to_s if key.downcase == name.downcase }
      ""
    end

    def timeout_error?(exc)
      return true if exc.is_a?(Net::OpenTimeout) || exc.is_a?(Net::ReadTimeout) || exc.is_a?(Timeout::Error)

      exc.message.to_s.downcase.include?("timed out")
    end
  end

  # Dispatches +client.bing.search(...)+ style calls to the underlying
  # operation id, validating that supplied keyword params are accepted.
  class OperationGroup
    REQUEST_OPTIONS = %i[_response_type _timeout _headers].freeze

    def initialize(client, operations)
      @client = client
      @operations = operations
    end

    def respond_to_missing?(name, include_private = false)
      @operations.key?(name.to_s) || super
    end

    def method_missing(name, **params)
      operation_id = @operations[name.to_s]
      return super if operation_id.nil?

      response_type = params.delete(:_response_type) || "auto"
      timeout = params.delete(:_timeout)
      headers = params.delete(:_headers)
      allowed = allowed_params(operation_id)
      unknown = params.keys.map(&:to_s) - allowed
      raise ArgumentError, "unexpected parameter(s) for #{operation_id}: #{unknown.sort.join(", ")}" unless unknown.empty?

      @client.request(operation_id, params, response_type: response_type, timeout: timeout, headers: headers)
    end

    private

    def allowed_params(operation_id)
      operation = OPERATIONS[operation_id] || {}
      allowed = (operation["pathParams"] || []).dup
      allowed += (operation["queryParams"] || []).map { |p| p["name"] }
      allowed += (operation["formParams"] || []).map { |p| p["name"] }
      allowed << operation["bodyParam"] if operation["bodyParam"]
      allowed << "body"
      allowed
    end
  end
end
