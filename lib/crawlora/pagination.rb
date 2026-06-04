# frozen_string_literal: true

module Crawlora
  # Pagination helpers shared by the client's #paginate / #paginate_items.
  module Pagination
    PAGE_PARAM_NAMES = %w[page offset].freeze

    module_function

    # First page/offset query parameter an operation exposes, or nil.
    def detect_page_param(operation)
      names = (operation["queryParams"] || []).map { |p| p["name"] }
      PAGE_PARAM_NAMES.find { |candidate| names.include?(candidate) }
    end

    # A page is empty when its `data` array (Crawlora envelope) or the page
    # itself is empty/blank.
    def page_empty?(response)
      data = response.is_a?(Hash) && response.key?("data") ? response["data"] : response
      return true if data.nil?
      return data.empty? if data.respond_to?(:empty?)

      !data
    end

    def default_start(page_param)
      page_param == "offset" ? 0 : 1
    end

    # Default item extractor: the response's `data` list (Crawlora envelope), or
    # the response itself when it is already an array.
    def default_items(response)
      return response["data"] if response.is_a?(Hash) && response["data"].is_a?(Array)
      return response if response.is_a?(Array)

      []
    end
  end
end
