# frozen_string_literal: true

module Crawlora
  # Base class for every error raised by the SDK. Carries the HTTP status, the
  # parsed API `code`/body, the raw response text, response headers, and the
  # request id (when request-id tracking is enabled).
  class Error < StandardError
    attr_reader :status, :code, :body, :raw_body, :headers, :request_id, :cause

    def initialize(message, status: 0, code: nil, body: nil, raw_body: "", headers: nil, request_id: nil, cause: nil)
      super(message)
      @status = status
      @code = code
      @body = body
      @raw_body = raw_body
      @headers = headers ? headers.dup : {}
      @request_id = request_id
      @cause = cause
    end
  end

  # Raised for 4xx API responses: the request was rejected by the API.
  class ClientError < Error; end

  # Raised for 5xx API responses: the API failed to handle a valid request.
  class ServerError < Error; end

  # Raised for transport failures and timeouts before a response arrived.
  class NetworkError < Error; end

  # Maps an HTTP status to the matching error class.
  def self.error_class_for(status)
    return ClientError if status >= 400 && status < 500
    return ServerError if status >= 500

    Error
  end
end
