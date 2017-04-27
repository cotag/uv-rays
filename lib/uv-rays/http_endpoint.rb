# frozen_string_literal: true

require 'uri'

module UV
    class CookieJar
        def initialize
            @jar = ::CookieJar::Jar.new
        end

        def set(uri, string)
            @jar.set_cookie(uri, string) rescue nil # drop invalid cookies
        end

        def get(uri)
            uri = URI.parse(uri) rescue nil
            uri ? @jar.get_cookies(uri).map(&:to_s) : []
        end

        def get_hash(uri)
            uri = URI.parse(uri) rescue nil
            cookies = {}
            if uri
                @jar.get_cookies(uri).each do |cookie|
                    cookies[cookie.name.to_sym] = cookie.value
                end
            end
            cookies
        end

        def clear_cookies
            @jar = ::CookieJar::Jar.new
        end
    end # CookieJar

    class HttpEndpoint
        class Connection < OutboundConnection
            def initialize(host, port, tls, client)
                @client = client
                @request = nil
                super(host, port)

                if tls
                    opts = {host_name: host}.merge(client.tls_options)
                    use_tls(opts)
                end
            end

            attr_accessor :request, :reason

            def on_read(data, *args) # user to define
                @client.data_received(data)
            end

            def post_init(*args)
            end

            def on_connect(transport) # user to define
                @client.connection_ready
            end

            def on_close # user to define
                req = @request
                @request = nil
                @client.connection_closed(req, @reason)
            end

            def close_connection(request = nil)
                if request.is_a? Http::Request
                    @request = request
                    super(:after_writing)
                else
                    super(request)
                end
            end
        end


        @@defaults = {
            :path => '/',
            :keepalive => true
        }


        def initialize(host, options = {})
            @queue = []
            @parser = Http::Parser.new
            @thread = reactor
            @connection = nil

            @options = @@defaults.merge(options)
            @tls_options = options[:tls_options] || {}
            @inactivity_timeout = options[:inactivity_timeout] || 10000
            @idle_timeout_method = method(:idle_timeout)

            if @inactivity_timeout > 0
                @timer = @thread.timer
            end

            uri = URI.parse host
            @port = uri.port
            @host = uri.host
            @scheme = uri.scheme
            @tls = @scheme == 'https'
            @cookiejar = CookieJar.new
            @middleware = []
        end


        attr_reader :inactivity_timeout, :thread
        attr_reader :tls_options, :port, :host, :tls, :scheme
        attr_reader :cookiejar, :middleware


        def get(options = {});     request(:get,     options); end
        def head(options = {});    request(:head,    options); end
        def delete(options = {});  request(:delete,  options); end
        def put(options = {});     request(:put,     options); end
        def post(options = {});    request(:post,    options); end
        def patch(options = {});   request(:patch,   options); end
        def options(options = {}); request(:options, options); end


        def request(method, options = {})
            options = @options.merge(options)
            options[:method] = method

            # Setup the request with callbacks
            request = Http::Request.new(self, options)
            request.then(proc { |response|
                if response.keep_alive
                    restart_timer
                else
                    close_connection
                end

                next_request

                response
            }, proc { |err|
                @parser.eof
                close_connection
                next_request
                ::Libuv::Q.reject(@thread, err)
            })

            @queue.unshift(request)

            next_request
            request
        end

        # Callbacks
        def connection_ready
            if @queue.length > 0
                restart_timer
                next_request
            else
                close_connection
            end
        end

        def connection_closed(request, reason)
            # We may have closed a previous connection
            if @parser.request && (request.nil? || request == @parser.request)
                @connection = nil
                stop_timer

                @parser.eof
            elsif request.nil? && @parser.request.nil? && @queue.length > 0
                req = @queue.pop
                req.reject(reason || :connection_failure)
            end
        end

        def data_received(data)
            restart_timer
            close_connection if @parser.received(data)
        end

        def cancel_all
            @queue.each do |request|
                request.reject(:cancelled)
            end
            if @parser.request
                @parser.request.reject(:cancelled)
                @parser.eof
            end
            @queue = []
            close_connection
        end


        private


        def next_request
            return if @parser.request || @queue.length == 0

            if @connection
                req = @queue.pop
                @connection.request = req
                @parser.new_request(req)

                req.execute(@connection)
            else
                new_connection
            end
        end

        def new_connection
            if @queue.length > 0 && @connection.nil?
                @connection = Connection.new(@host, @port, @tls, self)
                start_timer
            end
            @connection
        end

        def close_connection
            return if @connection.nil?
            @connection.close_connection(@parser.request)
            stop_timer
            @connection = nil
        end


        def start_timer
            return if @timer.nil?
            @timer.progress @idle_timeout_method
            @timer.start @inactivity_timeout
        end

        def restart_timer
            @timer.again unless @timer.nil?
        end

        def stop_timer
            @timer.stop unless @timer.nil?
        end

        def idle_timeout
            @parser.reason = :timeout if @parser.request
            @connection.reason = :timeout
            close_connection
        end
    end
end
