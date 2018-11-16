# frozen_string_literal: true

require 'timeout'
require 'uv-rays/time_queue'

module UV
    #
    # Provide a deferred with a maximum lifetime before the associated promise
    # auto-rejects.
    #
    class TimeBoundDeferred < ::Libuv::Q::Deferred
        def initialize(reactor, ttl)
            super(reactor)
            reactor.defer_queue.insert self, ttl
        end
    end
end

module Libuv
    class Reactor
        def defer_queue
            @defer_queue ||= ::UV::TimeQueue.new(@reactor, 1000) do |defer|
                defer.reject Timeout::Error.new
            end
        end
    end
end
