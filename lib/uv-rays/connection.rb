
module UV
    def self.try_connect(tcp, handler, server, port)
        if IPAddress.valid? server
            tcp.finally handler.method(:on_close)
            tcp.progress handler.method(:on_read)
            tcp.connect server, port do
                tcp.enable_nodelay
                tcp.start_tls(handler.using_tls) unless handler.using_tls == false

                # on_connect could call use_tls so must come after start_tls
                handler.on_connect(tcp)
                tcp.start_read
            end
        else
            tcp.loop.lookup(server).then(
                proc { |result|
                    UV.try_connect(tcp, handler, result[0][0], port)
                },
                proc { |failure|
                    # TODO:: Log error on loop
                    handler.on_close
                }
            )
        end
    end


    # @abstract
    class Connection
        attr_reader :using_tls

        def initialize
            @send_queue = []
            @paused = false
            @using_tls = false
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

        def stream_file(filename, type = :raw)
            file = @loop.file(filename, File::RDONLY)
            file.progress do    # File is open and available for reading
                file.send_file(@transport, type).finally do
                    file.close
                end
            end
            return file
        end

        def on_connect(transport) # user to define
        end

        def on_close # user to define
        end
    end

    class InboundConnection < TcpConnection
        def initialize(tcp)
            super()

            @loop = tcp.loop
            @transport = tcp
            @transport.finally method(:on_close)
            @transport.progress method(:on_read)
        end

        def use_tls(args = {})
            args[:server] = true

            if @transport.connected
                @transport.start_tls(args)
            else
                @using_tls = args
            end
        end
    end

    class OutboundConnection < TcpConnection

        def initialize(server, port)
            super()

            @loop = Libuv::Loop.current
            @server = server
            @port = port
            @transport = @loop.tcp

            ::UV.try_connect(@transport, self, @server, @port)
        end

        def use_tls(args = {})
            args.delete(:server)

            if @transport.connected
                @transport.start_tls(args)
            else
                @using_tls = args
            end
        end

        def reconnect(server = nil, port = nil)
            @loop = Libuv::Loop.current || @loop

            @transport = @loop.tcp
            @server = server || @server
            @port = port || @port

            ::UV.try_connect(@transport, self, @server, @port)
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
                # Async DNS resolution
                # Note:: send here will chain the promise
                tcp.loop.lookup(server).then do |result|
                    @transport.send result[0][0], recipient_port, data
                end
            end
        end
    end
end
