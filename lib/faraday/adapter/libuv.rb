require 'faraday'
require 'uv-rays'


module Faraday
  class Adapter < Middleware
    register_middleware libuv: :Libuv

    class Libuv < Faraday::Adapter
      def initialize(app, connection_options = {})
        @connection_options = connection_options
        super(app)
      end

      def call(env)
        super

        opts = {}
        if env[:url].scheme == 'https' && ssl = env[:ssl]
          tls_opts = opts[:tls_options] = {}

          # opts[:ssl_verify_peer] = !!ssl.fetch(:verify, true)
          # TODO:: Need to provide verify callbacks

          tls_opts[:cert_chain] = ssl[:ca_path] if ssl[:ca_path]
          tls_opts[:client_ca] = ssl[:ca_file] if ssl[:ca_file]
          #tls_opts[:client_cert] = ssl[:client_cert] if ssl[:client_cert]
          #tls_opts[:client_key]  = ssl[:client_key]  if ssl[:client_key]
          #tls_opts[:certificate] = ssl[:certificate] if ssl[:certificate]
          tls_opts[:private_key] = ssl[:private_key] if ssl[:private_key]
        end

        if (req = env[:request])
          opts[:inactivity_timeout] = req[:timeout] if req[:timeout]
        end

        error = nil
        thread = reactor
        if thread.running?
          error = perform_request(env, opts)
        else
          # Pretty much here for testing
          thread.run {
            error = perform_request(env, opts)
          }
        end

        # Re-raise the error out of the event loop
        # Really this is only required for tests as this will always run on the reactor
        raise error if error
        @app.call env
      rescue ::CoroutineRejection => err
        if err.value == :timeout
          raise Error::TimeoutError, err
        else
          raise Error::ConnectionFailed, err
        end
      end

      # TODO: support streaming requests
      def read_body(env)
        env[:body].respond_to?(:read) ? env[:body].read : env[:body]
      end
    end

    def perform_request(env, opts)
      conn = ::UV::HttpEndpoint.new(env[:url].to_s, opts.merge!(@connection_options))
      resp = co conn.request(env[:method].to_s.downcase.to_sym,
        headers: env[:request_headers],
        path: "/#{env[:url].to_s.split('/', 4)[-1]}",
        keepalive: false,
        body: read_body(env))

      save_response(env, resp.status.to_i, resp.body, resp) #, resp.reason_phrase)
      nil
    rescue Exception => e
      e
    end
  end
end
