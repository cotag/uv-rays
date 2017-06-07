require 'httpi'

module HTTPI; end
module HTTPI::Adapter; end
class HTTPI::Adapter::Libuv < HTTPI::Adapter::Base
    register :libuv, deps: %w(uv-rays)

    def initialize(request)
        @request = request
        @client = ::UV::HttpEndpoint.new request.url
    end

    attr_reader :client

    def request(method)
        @client.inactivity_timeout = @request.read_timeout if @request.read_timeout && @request.read_timeout > 0

        req = {
            path: @request.url,
            headers: @request.headers,
            body: @request.body
        }

        auth = @request.auth
        type = auth.type
        if auth.type
            creds = auth.credentials

            case auth.type
            when :basic
                req[:headers][:Authorization] = creds
            when :digest
                req[:digest] = {
                    user: creds[0],
                    password: creds[1]
                }
            when :ntlm
                req[:ntlm] = {
                    username: creds[0],
                    password: creds[1],
                    domain: creds[2] || ''
                }
            end
        end

        # Use co-routines to make non-blocking requests
        response = co @client.request(method, req)
        ::HTTPI::Response.new(response.status, response, response.body)
    end
end
