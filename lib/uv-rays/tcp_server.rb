# frozen_string_literal: true

require 'ipaddress' # IP Address parser

module UV
    class TcpServer < ::Libuv::TCP
        def initialize(reactor, server, port, klass, *args)
            super(reactor)

            @klass = klass
            @args = args

            if server == port && port.is_a?(Integer)
                # We are opening a socket descriptor
                open(server)
            else
                # Perform basic checks before attempting to bind address
                server = '127.0.0.1' if server == 'localhost'
                if IPAddress.valid? server
                    @server = server
                    bind(server, port) { |client| new_connection(client) }
                    listen(1024)
                else
                    raise ArgumentError, "Invalid server address #{server}"
                end
            end
        end


        private


        def new_connection(client)
            # prevent buffering
            client.enable_nodelay

            # create the connection class
            c = @klass.new(client)
            c.post_init *@args

            # start read after post init and call connected
            client.start_read
            c.on_connect(client)
        end
    end
end
