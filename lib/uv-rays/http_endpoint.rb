# frozen_string_literal: true

require 'uri'
require 'cookiejar'         # Manages cookies
require 'http-parser'       # Parses HTTP request / responses
require 'addressable/uri'   # URI parser
require 'uv-rays/http/encoding'
require 'uv-rays/http/request'
require 'uv-rays/http/parser'

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

    # HTTPS Proxy - connect to proxy
    # CONNECT #{target_host}:#{target_port} HTTP/1.0\r\n"
    # Proxy-Authorization: Basic #{encoded_credentials}\r\n
    # \r\n
    # Parse response =~ %r{\AHTTP/1\.[01] 200 .*\r\n\r\n}m
    # use_tls
    # send requests as usual

    # HTTP Proxy - connect to proxy
    # GET #{url_with_host} HTTP/1.1\r\n"
    # Proxy-Authorization: Basic #{encoded_credentials}\r\n
    # \r\n

    class HttpEndpoint
        class Connection < OutboundConnection
            def initialize(host, port, tls, proxy, client)
                @target_host = host
                @client = client
                @request = nil

                if proxy
                    super(proxy[:host], proxy[:port])
                    if tls
                        @negotiating = true
                        @proxy = proxy
                        @connect_host = host
                        @connect_port = port
                    end
                else
                    super(host, port)
                    start_tls if tls
                end
            end

            def start_tls
                opts = {host_name: @target_host}.merge(@client.tls_options)
                use_tls(opts)
            end

            def connect_send_handshake(target_host, target_port, proxy)
                header = String.new("CONNECT #{target_host}:#{target_port} HTTP/1.0\r\n")
                if proxy[:username] || proxy[:password]
                    encoded_credentials = Base64.strict_encode64([proxy[:username], proxy[:password]].join(":"))
                    header << "Proxy-Authorization: Basic #{encoded_credentials}\r\n"
                end
                header << "\r\n"
                write(header)
            end

            attr_accessor :request, :reason

            def on_read(data, *args)
                if @negotiating
                    @negotiating = false
                    if data =~ %r{\AHTTP/1\.[01] 200 .*\r\n\r\n}m
                        start_tls
                        @client.connection_ready
                    else
                        @reason = "Unexpected response from proxy: #{data}"
                        close_connection
                    end
                else
                    @client.data_received(data)
                end
            end

            def post_init(*args)
            end

            def on_connect(transport)
                if @negotiating
                    connect_send_handshake(@connect_host, @connect_port, @proxy)
                else
                    @client.connection_ready
                end
            end

            def on_close
                @client.connection_closed(@request, @reason)
            ensure
                @request = nil
                @client = nil
                @reason = nil
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

            uri = host.is_a?(::URI) ? host : ::URI.parse(host)
            @port = uri.port
            @host = uri.host

            default_port = uri.port == uri.default_port
            @encoded_host = default_port ? @host : "#{@host}:#{@port}"
            @proxy = @options[:proxy]

            @scheme = uri.scheme
            @tls = @scheme == 'https'
            @cookiejar = CookieJar.new
            @middleware = []

            @closing = false
            @connecting = false
        end


        attr_accessor :inactivity_timeout
        attr_reader :tls_options, :port, :host, :tls, :scheme, :encoded_host
        attr_reader :cookiejar, :middleware, :thread, :proxy


        def get(options = {});     request(:get,     options); end
        def head(options = {});    request(:head,    options); end
        def delete(options = {});  request(:delete,  options); end
        def put(options = {});     request(:put,     options); end
        def post(options = {});    request(:post,    options); end
        def patch(options = {});   request(:patch,   options); end
        def options(options = {}); request(:options, options); end


        def request(method, options = {})
            options = @options.merge(options)
            options[:method] = method.to_sym

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
                # @parser.eof
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
            # A connection can be closed while still connecting
            return if @closing

            @connecting = false
            if @queue.length > 0
                restart_timer
                next_request
            else
                close_connection
            end
        end

        def connection_closed(request, reason)
            # A connection might close due to a connection failure
            awaiting_close = @closing
            awaiting_connect = @connecting
            @closing = false
            @connecting = false

            # We may have closed a previous connection
            if @parser.request && (request.nil? || request == @parser.request)
                @connection = nil
                stop_timer

                @parser.eof
            elsif request.nil? && @parser.request.nil? && @queue.length > 0
                req = @queue.pop
                req.reject(reason || :connection_failure)
            end

            next_request if awaiting_close || awaiting_connect
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

        def http_proxy?
            @proxy && !@tls
        end


        private


        def next_request
            # Don't start a request while transitioning state
            return if @closing || @connecting
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
            # no new connections while transitioning state
            return if @closing || @connecting
            if @queue.length > 0 && @connection.nil?
                @connecting = true
                @connection = Connection.new(@host, @port, @tls, @proxy, self)
                start_timer
            end
            @connection
        end

        def close_connection
            # Close connection can be called while connecting
            return if @closing || @connection.nil?
            @closing = true
            @connection.close_connection
            stop_timer
            @connection = nil
        end


        def start_timer
            # Only start the timer if there is a connection starting or in place
            return if @closing || @connection.nil?
            @timer.cancel if @timer
            @timer = @thread.scheduler.in(@inactivity_timeout) do
                @timer = nil
                idle_timeout
            end
        end
        alias_method :restart_timer, :start_timer

        def stop_timer
            @timer.cancel unless @timer.nil?
            @timer = nil
        end

        def idle_timeout
            @parser.reason = :timeout if @parser.request
            @connection.reason = :timeout if @connection
            close_connection
        end
    end
end
