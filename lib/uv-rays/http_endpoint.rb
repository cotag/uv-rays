module UV
    class CookieJar
        def initialize
            @jar = ::CookieJar::Jar.new
        end

        def set(string, uri)
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
    end # CookieJar


    class HttpEndpoint < TcpConnection
        TRANSFER_ENCODING="TRANSFER_ENCODING"
        CONTENT_ENCODING="CONTENT_ENCODING"
        CONTENT_LENGTH="CONTENT_LENGTH"
        CONTENT_TYPE="CONTENT_TYPE"
        LAST_MODIFIED="LAST_MODIFIED"
        KEEP_ALIVE="CONNECTION"
        LOCATION="LOCATION"
        HOST="HOST"
        ETAG="ETAG"
        CRLF="\r\n"


        @@defaults = {
            :path => '/',
            :keepalive => true
        }

        attr_reader :host, :port, :using_tls, :loop, :cookiejar
        attr_reader :connect_timeout, :inactivity_timeout

        def initialize(uri, options = {})
            @connect_timeout     = options[:connect_timeout] ||= 5        # default connection setup timeout
            @inactivity_timeout  = options[:inactivity_timeout] ||= 10   # default connection inactivity (post-setup) timeout


            @using_tls = options[:tls] || options[:ssl] || false
            @using_tls.delete(:server) unless @using_tls == false

            uri = uri.kind_of?(Addressable::URI) ? uri : Addressable::URI::parse(uri.to_s)
            @https = uri.scheme == "https"
            uri.port ||= (@https ? 443 : 80)


            @loop = Libuv::Loop.current || Libuv::Loop.default
            @host = uri.host
            @port = uri.port
            #@transport = @loop.tcp

            # State flags
            @ready = false
            @connecting = false

            # Current requests
            @pending_requests = []
            @pending_responses = []
            @connection_pending = []
            @cookiejar = CookieJar.new

            # Callback methods
            @connection_method = method(:get_connection)
            @next_request_method = method(:next_request)
            @idle_timeout_method = method(:idle_timeout)
            @connect_timeout_method = method(:connect_timeout)

            # Used to indicate when we can start the next send
            @breakpoint = ::Libuv::Q::ResolvedPromise.new(@loop, true)

            # Manages the tokenising of response from the input stream
            @response = Http::Response.new(@pending_responses)

            # Timeout timer
            if @connect_timeout || @inactivity_timeout
                @timer = @loop.timer
            end
        end


        def get      options = {}, &blk;  request(:get,     options, &blk); end
        def head     options = {}, &blk;  request(:head,    options, &blk); end
        def delete   options = {}, &blk;  request(:delete,  options, &blk); end
        def put      options = {}, &blk;  request(:put,     options, &blk); end
        def post     options = {}, &blk;  request(:post,    options, &blk); end
        def patch    options = {}, &blk;  request(:patch,   options, &blk); end
        def options  options = {}, &blk;  request(:options, options, &blk); end


        def request(method, options = {}, &blk)
            options = @@defaults.merge(options)
            options[:method] = method

            # Setup the request with callbacks
            request = Http::Request.new(self, options)
            request.then proc { |result|
                if !result[:headers].keep_alive
                    @transport.close
                end
                result
            }

            ##
            # TODO:: Add middleware here
            request.then blk if blk

            # Add to pending requests and schedule using the breakpoint
            @pending_requests << request
            @breakpoint.finally @next_request_method
            if options[:pipeline] == true
                options[:keepalive] = true
            else
                @breakpoint = request
            end

            # return the request
            request
        end

        def middleware
            # TODO:: allow for middle ware
            []
        end

        def on_read(data, *args)
            @timer.again if @inactivity_timeout > 0
            # returns true on error
            # Response rejects the request
            if @response.receive(data)
                @transport.close
            end
        end

        def on_close
            @ready = false
            @connecting = false
            stop_timer

            # Reject any requests waiting on a response
            @pending_responses.each do |request|
                request.reject(:disconnected)
            end
            @pending_responses.clear
            
            # Re-connect if there are pending requests
            if not @connection_pending.empty?
                do_connect
            end
        end

        def on_connect(transport)
            @connecting = false
            @ready = true

            # Update timeouts
            stop_timer
            if @inactivity_timeout > 0
                @timer.progress @idle_timeout_method
                @timer.start @inactivity_timeout * 1000
            end

            # Kick off pending requests
            @response.reset!
            @connection_pending.each do |callback|
                callback.call
            end
            @connection_pending.clear
        end


        protected


        def do_connect
            @transport = @loop.tcp

            if @connect_timeout > 0
                @timer.progress @connect_timeout_method
                @timer.start @connect_timeout * 1000
            end

            @connecting = true
            ::UV.try_connect(@transport, self, @host, @port)
        end

        def get_connection(callback = nil, &blk)
            callback ||= blk

            if @connecting
                @connection_pending << callback
            elsif !@ready
                @connection_pending << callback
                do_connect
            elsif @transport.closing?
                @connection_pending << callback
            else
                callback.call(@connection)
            end
        end

        def connect_timeout
            @timer.stop
            @transport.close
            @connection_pending.each do |request|
                request.reject(:connection_timeout)
            end
        end

        def idle_timeout
            @timer.stop
            @transport.close
            @pending_responses.each do |request|
                request.reject(:idle_timeout)
            end
        end

        def next_request
            request = @pending_requests.shift

            get_connection do
                @pending_responses << request

                @timer.again if @inactivity_timeout > 0

                # TODO:: have request deal with the error internally
                request.send(@transport, proc { |err|
                    @transport.close
                    request.reject(err)
                })
            end
        end

        def stop_timer
            @timer.stop unless @timer.nil?
        end
    end
end
