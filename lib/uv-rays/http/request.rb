module UV
    module Http
        class Request < ::Libuv::Q::DeferredPromise
            include Encoding


            COOKIE = 'cookie'
            CONNECTION = :Connection
            CRLF="\r\n"


            attr_reader :path
            attr_reader :method
            attr_reader :headers, :options


            def cookies_hash
                @endpoint.cookiejar.get_hash(@uri)
            end

            def set_cookie(value)
                @endpoint.cookiejar.set(@uri, value)
            end
            

            def initialize(endpoint, options, using_ntlm)
                super(endpoint.loop, endpoint.loop.defer)

                @options = options
                @endpoint = endpoint
                @ntlm_retries = using_ntlm ? 0 : nil

                @path = options[:path]
                @method = options[:method]
                @uri = "#{endpoint.scheme}#{encode_host(endpoint.host, endpoint.port)}#{@path}"
            end

            def resolve(response, body)
                if @ntlm_retries == 0 && @headers.status == 401 && @headers[:"WWW-Authenticate"]
                    @options[:headers][:Authorization] = @endpoint.ntlm_auth_header(@headers[:"WWW-Authenticate"])
                    @ntlm_retries += 1

                    response.request = self
                    execute(*@exec_params)
                else
                    if @ntlm_retries == 1
                        @endpoint.clear_ntlm_header
                    end

                    @exec_params = nil
                    @defer.resolve({
                        headers: @headers,
                        body: body
                    })
                end
            end

            def reject(reason)
                @defer.reject(reason)
            end

            def execute(transport, error)
                head, body = build_request, @options[:body]
                @exec_params = [transport, error]

                @endpoint.middleware.each do |m|
                    head, body = m.request(self, head, body) if m.respond_to?(:request)
                end

                body = body.is_a?(Hash) ? form_encode_body(body) : body
                file = @options[:file]
                query = @options[:query]

                # Set the Content-Length if file is given
                head['content-length'] = File.size(file) if file

                # Set the Content-Length if body is given,
                # or we're doing an empty post or put
                if body
                    head['content-length'] = body.bytesize
                elsif method == :post or method == :put
                    # wont happen if body is set and we already set content-length above
                    head['content-length'] ||= 0
                end

                # Set content-type header if missing and body is a Ruby hash
                if !head['content-type'] and @options[:body].is_a? Hash
                    head['content-type'] = 'application/x-www-form-urlencoded'
                end

                request_header = encode_request(method, path, query)
                request_header << encode_headers(head)
                request_header << CRLF

                if body
                    request_header << body
                    transport.write(request_header).catch error
                elsif file
                    transport.write(request_header).catch error

                    # Send file
                    fileRef = @endpoint.loop.file file, File::RDONLY
                    fileRef.progress do
                        # File is open and available for reading
                        pSend = fileRef.send_file(transport, :raw)
                        pSend.catch error
                        pSend.finally do
                            fileRef.close
                        end
                    end
                    fileRef.catch error
                else
                    transport.write(request_header).catch error
                end
            end

            def notify(*args)
                @defer.notify(*args)
            end

            def set_headers(head)
                @headers = head
                if not @headers_callback.nil?
                    @headers_callback.call(@headers)
                end
            end

            def on_headers(callback, &blk)
                callback ||= blk
                if @headers.nil?
                    @headers_callback = callback
                else
                    callback.call(@headers)
                end
            end


            protected


            def encode_host(host, port)
                if port.nil? || port == 80 || port == 443
                    host
                else
                    host + ":#{port}"
                end
            end

            def build_request
                head = @options[:headers] ? munge_header_keys(@options[:headers]) : {}

                # Set the cookie header if provided
                @cookies = @endpoint.cookiejar.get(@uri)
                if cookie = head[COOKIE]
                    @cookies << encode_cookie(cookie)
                end
                head[COOKIE] = @cookies.compact.uniq.join("; ").squeeze(";") unless @cookies.empty?

                # Set connection close unless keep-alive
                if !@options[:keepalive]
                    head['connection'] = 'close'
                end

                # Set the Host header if it hasn't been specified already
                head['host'] ||= encode_host(@endpoint.host, @endpoint.port)

                # Set the User-Agent if it hasn't been specified
                if !head.key?('user-agent')
                    head['user-agent'] = "UV HttpClient"
                elsif head['user-agent'].nil?
                    head.delete('user-agent')
                end

                head
            end
        end
    end
end
