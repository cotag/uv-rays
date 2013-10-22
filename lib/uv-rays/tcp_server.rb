require 'ipaddress'
require 'dnsruby'


module UvRays
    class TcpServer < ::Libuv::TCP
        def initialize(loop, server, port, klass, *args)
            super(loop)

            @klass = klass
            @args = args
            @accept_method = method(:client_accepted)

            if server == port && port.is_a?(Fixnum)
                open(server)
            else
                server = '127.0.0.1' if server == 'localhost'
                if IPAddress.valid? server
                    @server = server
                    bind(server, port, method(:new_connection))
                    listen(1024)
                else
                    raise ArgumentError, "Invalid server address #{server}"
                end
            end
        end


        private


        def new_connection(server)
            server.accept @accept_method
        end

        def client_accepted(client)
            c = @klass.new(client)
            c.post_init *@args
            client.start_read       # Socket not paused
            c.on_connect(client)
        end
    end
end
