require 'ipaddress'
require 'dnsruby'


module UvRays
    def self.try_connect(tcp, handler, server, port)
        tcp.finally handler.method(:on_close)
        tcp.progress handler.method(:on_read)

        if IPAddress.valid? server
            tcp.connect server, port do
                tcp.start_read
                handler.on_connect(tcp)
            end
        else
            # TODO:: Async DNS resolution
        end
    end


    # @abstract
    class Connection
        def initialize
            @send_queue = []
            @paused = false
        end

        def pause
            @paused = true
            @transport.stop_read
        end

        def paused?
            @paused
        end

        def resume
            @paused = false
            @transport.start_read
        end

        # Compatible with TCP
        def close_connection(*args)
            @transport.close
        end

        def on_read(data, *args) # user to define
        end

        def post_init(*args)
        end
    end

    class TcpConnection < Connection
        def write(data)
            @transport.write(data)
        end

        def close_connection(after_writing = false)
            if after_writing
                @transport.shutdown
            else
                @transport.close
            end
        end

        def stream_file(filename)
        end

        def on_connect(transport) # user to define
        end

        def on_close # user to define
        end
    end

    class InboundConnection < TcpConnection
        def initialize(tcp)
            super()

            @transport = tcp
            @transport.finally method(:on_close)
            @transport.progress method(:on_read)
        end
    end

    class OutboundConnection < TcpConnection

        def initialize(server, port)
            super()

            @loop = Libuv::Loop.current
            @server = server
            @port = port
            @transport = @loop.tcp

            ::UvRays.try_connect(@transport, self, @server, @port)
        end

        def reconnect(server = nil, port = nil)
            @loop = Libuv::Loop.current || @loop

            @transport = @loop.tcp
            @server = server || @server
            @port = port || @port

            ::UvRays.try_connect(@transport, self, @server, @port)
        end
    end

    class DatagramConnection < Connection
        def initialize(server = nil, port = nil)
            super()

            @loop = Libuv::Loop.current
            @transport = @loop.udp
            @transport.progress method(:on_read)

            if not server.nil?
                server = '127.0.0.1' if server == 'localhost'
                if IPAddress.valid? server
                    @transport.bind(server, port)
                else
                    raise ArgumentError, "Invalid server address #{server}"
                end
            end

            @transport.start_read
        end

        def send_datagram(data, recipient_address, recipient_port)
            if IPAddress.valid? recipient_address
                @transport.send recipient_address, recipient_port, data
            else
                # TODO:: Async DNS resolution
            end
        end
    end
end
