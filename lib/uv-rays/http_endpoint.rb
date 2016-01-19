require 'rubyntlm'


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


    class HttpEndpoint < OutboundConnection
        TRANSFER_ENCODING="TRANSFER_ENCODING".freeze
        CONTENT_ENCODING="CONTENT_ENCODING".freeze
        CONTENT_LENGTH="CONTENT_LENGTH".freeze
        CONTENT_TYPE="CONTENT_TYPE".freeze
        LAST_MODIFIED="LAST_MODIFIED".freeze
        KEEP_ALIVE="CONNECTION".freeze
        LOCATION="LOCATION".freeze
        HOST="HOST".freeze
        ETAG="ETAG".freeze
        CRLF="\r\n".freeze
        HTTPS="https://".freeze
        HTTP="http://".freeze


        @@defaults = {
            :path => '/',
            :keepalive => true
        }

        attr_reader :scheme, :host, :port, :using_tls, :loop, :cookiejar
        attr_reader :inactivity_timeout

        def initialize(uri, options = {})
            @inactivity_timeout  = options[:inactivity_timeout] ||= 10000   # default connection inactivity (post-setup) timeout
            @ntlm_creds = options[:ntlm]

            uri = uri.kind_of?(Addressable::URI) ? uri : Addressable::URI::parse(uri.to_s)
            @https = uri.scheme == "https"
            uri.port ||= (@https ? 443 : 80)
            @scheme = @https ? HTTPS : HTTP


            @loop = Libuv::Loop.current || Libuv::Loop.default
            @host = uri.host
            @port = uri.port
            #@transport = @loop.tcp

            # State flags
            @closed = true
            @closing = false
            @connecting = false

            # Current requests
            @pending_requests = []
            @staging_request = nil
            @waiting_response = nil
            @cookiejar = CookieJar.new

            # Callback methods
            @idle_timeout_method = method(:idle_timeout)

            # Manages the tokenising of response from the input stream
            @response = Http::Response.new

            # Timeout timer
            if @inactivity_timeout > 0
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
            request = Http::Request.new(self, options, @ntlm_creds)
            request.then(proc { |result|
                @waiting_response = nil

                if @closed || result[:headers].keep_alive
                    next_request
                else
                    @closing = true
                    @transport.close
                end

                result
            }, proc { |err|
                @waiting_response = nil
                next_request

                ::Libuv::Q.reject(@loop, err)
            })

            ##
            # TODO:: Add response middleware here
            request.then blk if blk

            # Add to pending requests and schedule using the breakpoint
            @pending_requests << request
            if !@waiting_response && !@staging_request
                next_request
            end

            # return the request
            request
        end


        def next_request
            @staging_request = @pending_requests.shift
            process_request unless @staging_request.nil?
        end

        def process_request
            if @closed && !@connecting
                @transport = @loop.tcp

                @connecting = @staging_request
                ::UV.try_connect(@transport, self, @host, @port)
            elsif !@closing
                try_send
            end
        end


        def on_connect(transport)
            @connecting = false
            @closed = false

            # start tls if connection is encrypted
            use_tls() if @https

            # Update timeouts
            stop_timer
            if @inactivity_timeout > 0
                @timer.progress @idle_timeout_method
                @timer.start @inactivity_timeout
            end

            # Kick off pending requests
            @response.reset!
            try_send  # we only connect if there is a request waiting
        end


        def on_close
            @closed = true
            @ntlm_auth = nil
            clear_staging = @connecting == @staging_request
            @connecting = false
            stop_timer

            # On close may be called before on data
            @loop.next_tick do
                if @closing
                    @closing = false
                    @connecting = false

                    if @staging_request
                        process_request
                    else
                        next_request
                    end
                else
                    if clear_staging
                        @staging_request.reject(:connection_refused)
                    elsif @waiting_response
                        # Flush any processing request
                        @response.eof if @response.request

                        # Reject any requests waiting on a response
                        @waiting_response.reject(:disconnected)
                    elsif @staging_request
                        # Try reconnect
                        process_request
                    end
                end
            end
        end

        def try_send
            @waiting_response = @staging_request
            @response.request = @staging_request
            @staging_request = nil

            if @ntlm_creds
                opts = @waiting_response.options
                opts[:headers] ||= {}
                opts = opts[:headers]
                opts[:Authorization] = ntlm_auth_header
            end

            @timer.again if @inactivity_timeout > 0
            @waiting_response.execute(@transport, proc { |err|
                @transport.close
                @waiting_response.reject(err)
            })
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

        def close_connection(after_writing = false)
            stop_timer
            reqs = @pending_requests
            @pending_requests.clear
            reqs.each do |request|
                request.reject(:close_connection)
            end
            super(after_writing) if @transport
        end

        def ntlm_auth_header(challenge = nil)
            if @ntlm_auth && challenge.nil?
                return @ntlm_auth
            elsif challenge
                scheme, param_str = parse_ntlm_challenge_header(challenge)
                if param_str.nil?
                    @ntlm_auth = nil
                    return ntlm_auth_header(@ntlm_creds)
                else
                    t2 = Net::NTLM::Message.decode64(param_str)
                    t3 = t2.response(@ntlm_creds, ntlmv2: true)
                    @ntlm_auth = "NTLM #{t3.encode64}"
                    return @ntlm_auth
                end
            else
                domain = @ntlm_creds[:domain]
                t1 = Net::NTLM::Message::Type1.new()
                t1.domain = domain if domain
                @ntlm_auth = "NTLM #{t1.encode64}"
                return @ntlm_auth
            end
        end

        def clear_ntlm_header
            @ntlm_auth = nil
        end


        protected


        def idle_timeout
            @timer.stop
            @transport.close
        end

        def stop_timer
            @timer.stop unless @timer.nil?
        end

        def parse_ntlm_challenge_header(challenge)
            scheme, param_str = challenge.scan(/\A(\S+)(?:\s+(.*))?\z/)[0]
            return nil if scheme.nil?
            return scheme, param_str
        end
    end
end
