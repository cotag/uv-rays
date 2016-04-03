require 'rubyntlm'

module UV
    module Http
        class Request < ::Libuv::Q::DeferredPromise
            include Encoding


            COOKIE = 'cookie'
            CONNECTION = :Connection
            CRLF="\r\n"


            attr_reader :path, :method, :options


            def cookies_hash
                @endpoint.cookiejar.get_hash(@uri)
            end

            def set_cookie(value)
                @endpoint.cookiejar.set(@uri, value)
            end
            

            def initialize(endpoint, options)
                super(endpoint.thread, endpoint.thread.defer)

                @options = options
                @endpoint = endpoint
                @ntlm_creds = options[:ntlm]

                @path = options[:path]
                @method = options[:method]
                @uri = "#{endpoint.scheme}#{encode_host(endpoint.host, endpoint.port)}#{@path}"

                @error = proc { |reason| reject(reason) }
            end



            def resolve(response, parser = nil)
                if response.status == 401 && @ntlm_creds && @ntlm_retries == 0 && response[:"WWW-Authenticate"]
                    @options[:headers][:Authorization] = ntlm_auth_header(response[:"WWW-Authenticate"])
                    @ntlm_retries += 1

                    execute(@transport)
                    false
                else
                    @transport = nil
                    @defer.resolve(response)
                    true
                end
            end

            def reject(reason)
                @defer.reject(reason)
            end

            def execute(transport)
                # configure ntlm request headers
                if @options[:ntlm]
                    @options[:headers] ||= {}
                    @options[:headers][:Authorization] ||= ntlm_auth_header
                end

                head, body = build_request, @options[:body]
                @transport = transport

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
                    transport.write(request_header).catch @error
                elsif file
                    transport.write(request_header).catch @error

                    # Send file
                    fileRef = @endpoint.loop.file file, File::RDONLY
                    fileRef.progress do
                        # File is open and available for reading
                        pSend = fileRef.send_file(transport, :raw)
                        pSend.catch @error
                        pSend.finally do
                            fileRef.close
                        end
                    end
                    fileRef.catch @error
                else
                    transport.write(request_header).catch @error
                end
            end

            def notify(*args)
                @defer.notify(*args)
            end

            def set_headers(head)
                @headers_callback.call(head) if @headers_callback
            end



            def on_headers(callback, &blk)
                @headers_callback = callback
            end

            def streaming?
                @options[:streaming]
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
                    @ntlm_retries = 0
                    domain = @ntlm_creds[:domain]
                    t1 = Net::NTLM::Message::Type1.new()
                    t1.domain = domain if domain
                    @ntlm_auth = "NTLM #{t1.encode64}"
                    return @ntlm_auth
                end
            end

            def parse_ntlm_challenge_header(challenge)
                scheme, param_str = challenge.scan(/\A(\S+)(?:\s+(.*))?\z/)[0]
                return nil if scheme.nil?
                return scheme, param_str
            end
        end
    end
end
