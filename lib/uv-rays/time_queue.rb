# frozen_string_literal: true

require 'uv-rays/scheduler/time'

module UV
    #
    # Time-based queue structure. Objects may be inserted with an associated
    # TTL, which when expired, will flag the object for dequeue and yield it to
    # an expiry handler.
    #
    class TimeQueue
        MAX_TICK = 1 << (1.size * 8 - 2) - 1 # upper-bound of Fixnum

        def initialize(reactor, sweep_interval = 1000, &expiry_handler)
            @reactor = reactor
            @sweep_interval = Scheduler.parse_in sweep_interval
            @expiry_handler = expiry_handler

            @queue = {}

            @tick = 0
            @max_ttl = MAX_TICK * sweep_interval
        end

        def on_expiry(&handler)
            @expiry_handler = handler
        end

        def insert(obj, ttl)
            raise ArgumentError, 'ttl exceeds max trackable' if ttl > @max_ttl

            expire_at = (@tick + ttl / @sweep_interval) % MAX_TICK

            @reactor.schedule do
                @queue[expire_at] ||= []
                @queue[expire_at] << obj
                start_sweep
            end

            nil
        end

        protected

        def start_sweep
            @sweep ||= @reactor.scheduler.every(@sweep_interval) do
                expired = @queue.delete(@tick)
                expired&.each { |obj| @expiry_handler&.call obj }

                @tick = @tick.next % MAX_TICK

                stop_sweep if @queue.empty?
            end
        end

        def stop_sweep
            @sweep&.cancel
            @sweep = nil
        end
    end
end
