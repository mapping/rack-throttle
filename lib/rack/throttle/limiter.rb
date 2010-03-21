module Rack; module Throttle
  ##
  # This is the base class for rate limiter implementations.
  #
  # @example Defining a rate limiter subclass
  #   class MyLimiter < Limiter
  #     def allowed?(request)
  #       # TODO: custom logic goes here
  #     end
  #   end
  #
  class Limiter
    attr_reader :app
    attr_reader :options

    ##
    # @param  [#call]                      app
    # @param  [Hash{Symbol => Object}]     options
    # @option options [String]  :cache      (Hash.new)
    # @option options [String]  :key        (nil)
    # @option options [String]  :key_prefix (nil)
    # @option options [Integer] :code       (403)
    # @option options [String]  :message    ("Rate Limit Exceeded")
    def initialize(app, options = {})
      @app, @options = app, options
    end

    ##
    # @param  [Hash{String => String}] env
    # @return [Array(Integer, Hash, #each)]
    # @see    http://rack.rubyforge.org/doc/SPEC.html
    def call(env)
      request = Rack::Request.new(env)
      allowed?(request) ? app.call(env) : rate_limit_exceeded
    end

    ##
    # Returns `false` if the rate limit has been exceeded for the given
    # `request`, or `true` otherwise.
    #
    # Override this method in subclasses that implement custom rate limiter
    # strategies.
    #
    # @param  [Rack::Request] request
    # @return [Boolean]
    def allowed?(request)
      case
        when whitelisted?(request) then true
        when blacklisted?(request) then false
        else true # override in subclasses
      end
    end

    ##
    # Returns `true` if the originator of the given `request` is whitelisted
    # (not subject to further rate limits).
    #
    # The default implementation always returns `false`. Override this
    # method in a subclass to implement custom whitelisting logic.
    #
    # @param  [Rack::Request] request
    # @return [Boolean]
    # @abstract
    def whitelisted?(request)
      false
    end

    ##
    # Returns `true` if the originator of the given `request` is blacklisted
    # (not honoring rate limits, and thus permanently forbidden access
    # without the need to maintain further rate limit counters).
    #
    # The default implementation always returns `false`. Override this
    # method in a subclass to implement custom blacklisting logic.
    #
    # @param  [Rack::Request] request
    # @return [Boolean]
    # @abstract
    def blacklisted?(request)
      false
    end

    protected

    ##
    # @return [Hash]
    def cache
      case cache = (@options[:cache] ||= {})
        when Proc then cache.call
        else cache
      end
    end

    ##
    # @param  [String] key
    def cache_has?(key)
      case
        when cache.respond_to?(:has_key?)
          cache.has_key?(key)
        when cache.respond_to?(:get)
          cache.get(key) rescue false
        else false
      end
    end

    ##
    # @param  [String] key
    # @return [Object]
    def cache_get(key, default = nil)
      case
        when cache.respond_to?(:[])
          cache[key] || default
        when cache.respond_to?(:get)
          cache.get(key) || default
      end
    end

    ##
    # @param  [String] key
    # @param  [Object] value
    # @return [void]
    def cache_set(key, value)
      case
        when cache.respond_to?(:[]=)
          cache[key] = value
        when cache.respond_to?(:set)
          cache.set(key, value)
      end
    end

    ##
    # @param  [Rack::Request] request
    # @return [String]
    def cache_key(request)
      id = client_identifier(request)
      case
        when options.has_key?(:key)
          options[:key].call(request)
        when options.has_key?(:key_prefix)
          [options[:key_prefix], id].join(':')
        else id
      end
    end

    ##
    # @param  [Rack::Request] request
    # @return [String]
    def client_identifier(request)
      request.ip.to_s
    end

    ##
    # @param  [Rack::Request] request
    # @return [Float]
    def request_start_time(request)
      case
        when request.env.has_key?('HTTP_X_REQUEST_START')
          request.env['HTTP_X_REQUEST_START'].to_f / 1000
        else
          Time.now.to_f
      end
    end

    ##
    # Outputs a `Rate Limit Exceeded` error.
    #
    # @param  [Integer] code
    # @param  [String]  message
    # @return [Array(Integer, Hash, #each)]
    def rate_limit_exceeded(code = nil, message = nil)
      http_error(code || options[:code] || 403,
        message || options[:message] || 'Rate Limit Exceeded')
    end

    ##
    # Outputs an HTTP `4xx` or `5xx` response.
    #
    # @param  [Integer]       code
    # @param  [String, #to_s] message
    # @return [Array(Integer, Hash, #each)]
    def http_error(code, message = nil)
      [code, {'Content-Type' => 'text/plain; charset=utf-8'},
        http_status(code) + (message.nil? ? "\n" : " (#{message})\n")]
    end

    ##
    # Returns the standard HTTP status message for the given status `code`.
    #
    # @param  [Integer] code
    # @return [String]
    def http_status(code)
      [code, Rack::Utils::HTTP_STATUS_CODES[code]].join(' ')
    end
  end
end; end
