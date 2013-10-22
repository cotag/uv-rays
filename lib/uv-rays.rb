require 'libuv'
require 'uv-rays/buffered_tokenizer'
require 'uv-rays/abstract_tokenizer'
require 'uv-rays/connection'
require 'uv-rays/tcp_server'


module UvRays

    # @private
    def self.klass_from_handler(klass, handler = nil, *args)
        klass = if handler and handler.is_a?(Class)
            raise ArgumentError, "must provide module or subclass of #{klass.name}" unless klass >= handler
            handler
        elsif handler
            begin
                handler::UR_CONNECTION_CLASS
            rescue NameError
                handler::const_set(:UR_CONNECTION_CLASS, Class.new(klass) {include handler})
            end
        else
            klass
        end

        arity = klass.instance_method(:post_init).arity
        expected = arity >= 0 ? arity : -(arity + 1)
        if (arity >= 0 and args.size != expected) or (arity < 0 and args.size < expected)
            raise ArgumentError, "wrong number of arguments for #{klass}#post_init (#{args.size} for #{expected})"
        end

        klass
    end


    def self.connect(server, port, handler, *args)
        klass = klass_from_handler(OutboundConnection, handler, *args)

        c = klass.new server, port
        c.post_init *args
        c
    end

    def self.start_server(server, port, handler, *args)
        loop = Libuv::Loop.current   # Get the current event loop
        raise ThreadError, "There is no Libuv Loop running on the current thread" if loop.nil?

        klass = klass_from_handler(InboundConnection, handler, *args)
        UvRays::TcpServer.new loop, server, port, klass, *args
    end

    def self.attach_server(sock, handler, *args)
        loop = Libuv::Loop.current   # Get the current event loop
        raise ThreadError, "There is no Libuv Loop running on the current thread" if loop.nil?

        klass = klass_from_handler(InboundConnection, handler, *args)
        sd = sock.respond_to?(:fileno) ? sock.fileno : sock

        UvRays::TcpServer.new loop, sd, sd, klass, *args
    end

    def self.open_datagram_socket(handler, server = nil, port = nil, *args)
        klass = klass_from_handler(DatagramConnection, handler, *args)

        c = klass.new server, port
        c.post_init *args
        c
    end
end

# Alias for {UvRays}
UV = UvRays

