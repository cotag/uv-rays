# frozen_string_literal: true

require 'libuv'

module UV
    autoload :Ping, 'uv-rays/ping'

    # In-memory event scheduling
    autoload :Scheduler, 'uv-rays/scheduler'

    # Intelligent stream buffering
    autoload :BufferedTokenizer, 'uv-rays/buffered_tokenizer'
    autoload :AbstractTokenizer, 'uv-rays/abstract_tokenizer'

    # TCP Connections
    autoload :TcpServer,          'uv-rays/tcp_server'
    autoload :Connection,         'uv-rays/connection'
    autoload :TcpConnection,      'uv-rays/connection'
    autoload :InboundConnection,  'uv-rays/connection'
    autoload :OutboundConnection, 'uv-rays/connection'
    autoload :DatagramConnection, 'uv-rays/connection'

    # HTTP related methods
    autoload :HttpEndpoint, 'uv-rays/http_endpoint'

    # Time-based object queue
    autoload :TimeQueue, 'uv-rays/time_queue'

    # Promises with a max time-to-live
    autoload :TimeBoundDeferred, 'uv-rays/time_bound_deferred'


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
        thread = reactor   # Get the reactor running on this thread
        raise ThreadError, "There is no Libuv reactor running on the current thread" if thread.nil?

        klass = klass_from_handler(InboundConnection, handler, *args)
        UV::TcpServer.new thread, server, port, klass, *args
    end

    def self.attach_server(sock, handler, *args)
        thread = reactor   # Get the reactor running on this thread
        raise ThreadError, "There is no Libuv reactor running on the current thread" if thread.nil?

        klass = klass_from_handler(InboundConnection, handler, *args)
        sd = sock.respond_to?(:fileno) ? sock.fileno : sock

        UV::TcpServer.new thread, sd, sd, klass, *args
    end

    def self.open_datagram_socket(handler, server = nil, port = nil, *args)
        klass = klass_from_handler(DatagramConnection, handler, *args)

        c = klass.new server, port
        c.post_init *args
        c
    end
end

module Libuv
    class Reactor
        def scheduler
            @scheduler ||= ::UV::Scheduler.new(@reactor)
            @scheduler
        end

        def defer(ttl: nil)
            if ttl
                ::UV::TimeBoundDeferred.new(@reactor, ttl: tll)
            else
                super()
            end
        end
    end
end
