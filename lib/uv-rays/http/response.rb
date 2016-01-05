module UV
    module Http
        class Headers < Hash
            # The HTTP version returned
            attr_accessor :http_version

            # The status code (as an integer)
            attr_accessor :status

            # Cookies at the time of the request
            attr_accessor :cookies

            attr_accessor :keep_alive
        end

        class Response
            def initialize
                @parser = ::HttpParser::Parser.new(self)
                @state = ::HttpParser::Parser.new_instance
                @state.type = :response
            end


            attr_accessor :request


            # Called on connection disconnect
            def reset!
                @state.reset!
            end

            # Socket level data is forwarded as it arrives
            def receive(data)
                # Returns true if error
                if @parser.parse(@state, data)
                    if @request
                        @request.reject(@state.error)
                        @request = nil
                        return true
                    #else # silently fail here
                    #    p 'parse error and no request..'
                    #    p @state.error
                    end
                end

                false
            end

            ##
            # Parser Callbacks:
            def on_message_begin(parser)
                @headers = Headers.new
                @body = ''
                @chunked = false
            end

            def on_status(parser, data)
                # Different HTTP versions have different defaults
                if @state.http_minor == 0
                    @close_connection = true
                else
                    @close_connection = false
                end
            end

            def on_header_field(parser, data)
                @header = data.to_sym
            end

            def on_header_value(parser, data)
                case @header
                when :"Set-Cookie"
                    @request.set_cookie(data)

                when :Connection
                    # Overwrite the default
                    @close_connection = data == 'close'

                when :"Transfer-Encoding"
                    # If chunked we'll buffer streaming data for notification
                    @chunked = data == 'chunked'

                else
                    @headers[@header] = data
                end
            end

            def on_headers_complete(parser)
                headers = @headers
                @headers = nil
                @header = nil

                # https://github.com/joyent/http-parser indicates we should extract
                # this information here
                headers.http_version = @state.http_version
                headers.status = @state.http_status
                headers.cookies = @request.cookies_hash
                headers.keep_alive = !@close_connection

                # User code may throw an error
                # Errors will halt the processing and return a PAUSED error
                @request.set_headers(headers)
            end

            def on_body(parser, data)
                @body << data
                # TODO:: What if it is a chunked response body?
                # We should buffer complete chunks
                @request.notify(data)
            end

            def on_message_complete(parser)
                req = @request
                bod = @body

                # Clean up memory
                @request = nil
                @body = nil

                req.resolve(self, bod)
            end

            # We need to flush the response on disconnect if content-length is undefined
            # As per the HTTP spec
            def eof
                if @headers.nil? && @request.headers && @request.headers[:'Content-Length'].nil?
                    on_message_complete(nil)
                else
                    # Reject if this is a partial response
                    @request.reject(:partial_response)
                end
            end
        end
    end
end
