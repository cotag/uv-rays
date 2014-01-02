require 'libuv'


# In-memory event scheduling
require 'set'               # ruby std lib
require 'bisect'            # insert into a sorted array
require 'tzinfo'            # timezone information
require 'uv-rays/scheduler/cron'
require 'uv-rays/scheduler/time'
require 'uv-rays/scheduler'

# Intelligent stream buffering
require 'uv-rays/buffered_tokenizer'
require 'uv-rays/abstract_tokenizer'

# TCP Connections
require 'ipaddress'         # IP Address parser
require 'uv-rays/tcp_server'
require 'uv-rays/connection'

# HTTP related methods
require 'cookiejar'         # Manages cookies
require 'http-parser'       # Parses HTTP request / responses
require 'addressable/uri'   # URI parser
require 'uv-rays/http/encoding'
require 'uv-rays/http/request'
require 'uv-rays/http/response'
require 'uv-rays/http_endpoint'



module UV

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
        UV::TcpServer.new loop, server, port, klass, *args
    end

    def self.attach_server(sock, handler, *args)
        loop = Libuv::Loop.current   # Get the current event loop
        raise ThreadError, "There is no Libuv Loop running on the current thread" if loop.nil?

        klass = klass_from_handler(InboundConnection, handler, *args)
        sd = sock.respond_to?(:fileno) ? sock.fileno : sock

        UV::TcpServer.new loop, sd, sd, klass, *args
    end

    def self.open_datagram_socket(handler, server = nil, port = nil, *args)
        klass = klass_from_handler(DatagramConnection, handler, *args)

        c = klass.new server, port
        c.post_init *args
        c
    end
end

